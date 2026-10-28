part of 'auth_provider.dart';

extension _AccountConnectionMaintenance on AuthNotifier {
  Future<void> _restoreBackendConnection({
    bool force = false,
    bool reportErrors = false,
  }) async {
    if (!mounted || !_accountBackendConfig.isConfigured) return;
    _expireConnectionPrivileges();
    final pending = _connectionCheck;
    if (pending != null) return pending;
    if (!force && !_connectionRetry.canAttempt(DateTime.now().toUtc())) return;
    final operation = _checkBackendConnection(
      _connectionGeneration,
      force: force,
      reportErrors: reportErrors,
    );
    _connectionCheck = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectionCheck, operation)) _connectionCheck = null;
    }
  }

  Future<void> _checkBackendConnection(
    int generation, {
    required bool force,
    required bool reportErrors,
  }) async {
    AccountSessionSnapshot? session;
    String? deviceId;
    bool current() => mounted && generation == _connectionGeneration;
    try {
      session = await _sessionManager.read();
      if (!current()) return;
      if (session == null || session.accessToken.isEmpty) {
        if (reportErrors) {
          throw const AccountBackendError('signed_out', 'Sign in first.');
        }
        return;
      }
      if (!force &&
          _connectionState.backendStatus == 'active' &&
          session.expiresAt?.isAfter(
                DateTime.now().toUtc().add(const Duration(minutes: 2)),
              ) ==
              true) {
        return;
      }
      _connectionState = _connectionState.copyWith(
        email: session.email,
        backendStatus: 'refreshingStoredSession',
        clearBackendError: true,
        // Retain only already verified, unexpired in-memory privileges.
        // Startup never derives privileges from the stored role.
      );
      session = await _sessionManager.validSession();
      if (!current()) return;
      deviceId = session.deviceId ?? await _ensureBackendDeviceId();
      if (!current()) return;
      AccountBackendProfile profile;
      try {
        profile = await _accountBackendService.refreshSession(
          accessToken: session.accessToken,
          deviceId: deviceId,
          friendlyName: 'Windows',
        );
      } on AccountBackendError catch (error) {
        if (error.statusCode != 401 || !current()) rethrow;
        // A server can reject an access token before its local expiry.
        // Retry this profile check only once, never security mutations.
        session = await _sessionManager.validSession(forceRefresh: true);
        if (!current()) return;
        profile = await _accountBackendService.refreshSession(
          accessToken: session.accessToken,
          deviceId: deviceId,
          friendlyName: 'Windows',
        );
      }
      if (!current()) return;
      await _saveBackendSessionSnapshot(session, profile, deviceId);
      if (!current()) return;
      await applyBackendProfile(
        profile,
        deviceId: deviceId,
        tokenExpiry: session.expiresAt,
      );
      _connectionRetry.succeeded();
    } catch (error) {
      if (!current()) return;
      if (error is AccountBackendError && error.code == 'session_changed') {
        return;
      }
      final disabled =
          error is AccountBackendError &&
          (error.code == 'account_disabled' || error.code == 'user_banned');
      final clockError =
          error is AccountBackendError && error.code == 'clock_rollback';
      final needsSignIn =
          AccountSessionManager.requiresSignIn(error) ||
          (error is AccountBackendError && error.statusCode == 401);
      _connectionRetry.failed(
        DateTime.now().toUtc(),
        requiresSignIn: needsSignIn || disabled,
      );
      if (needsSignIn || disabled) {
        await _clearStoredBackendSession();
        if (!current()) return;
        _connectionState = AuthState(
          accountBackendEnabled: true,
          backendStatus: disabled ? 'disabledAccount' : 'sessionExpired',
          backendError:
              disabled ? 'This account is disabled.' : 'Please sign in again.',
          rememberMe: _connectionState.rememberMe,
          lastEmailUsed: session?.email ?? _connectionState.lastEmailUsed,
        );
      } else {
        // Only transport/server unavailability permits signed offline grace.
        // Provider revocation, disabled accounts and configuration errors do not.
        final temporary =
            error is SocketException ||
            error is TimeoutException ||
            (error is AccountBackendError &&
                ((error.statusCode ?? 0) >= 500 || error.statusCode == 429));
        if (temporary &&
            _applyOfflineGrace(session, deviceId ?? session?.deviceId)) {
          if (reportErrors) rethrow;
          return;
        }
        _connectionState = _connectionState.copyWith(
          email: session?.email,
          isPro: false,
          isAdmin: false,
          backendStatus:
              clockError ? 'clockRollbackDetected' : 'connectionRetryWaiting',
          backendError:
              clockError
                  ? 'Check the date and time on this computer.'
                  : 'Account connection unavailable. Retrying automatically.',
        );
        // Keep encrypted refresh credentials on offline/5xx/local failures.
      }
      if (reportErrors) rethrow;
    }
  }

  void _expireConnectionPrivileges() {
    final snapshot = _connectionState;
    final now = DateTime.now().toUtc();
    final expiry =
        snapshot.backendStatus == 'offlineGraceActive'
            ? snapshot.offlineGraceExpiry
            : snapshot.backendTokenExpiry;
    final entitlementExpiry = snapshot.entitlementExpiresAt;
    if ((snapshot.isPro || snapshot.isAdmin) &&
        ((expiry != null && !expiry.isAfter(now)) ||
            (entitlementExpiry != null && !entitlementExpiry.isAfter(now)))) {
      _connectionState = snapshot.copyWith(isPro: false, isAdmin: false);
    }
  }
}
