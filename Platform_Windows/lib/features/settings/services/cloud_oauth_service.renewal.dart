part of 'cloud_oauth_service.dart';

class CloudOAuthCredentials {
  final String googleClientId;
  final String googleClientSecret;
  final String dropboxClientId;
  const CloudOAuthCredentials({
    this.googleClientId = googleDriveOAuthClientId,
    this.googleClientSecret = googleDriveOAuthClientSecret,
    this.dropboxClientId = dropboxOAuthClientId,
  });
}

enum CloudConnectionStatus {
  disconnected,
  checking,
  available,
  retrying,
  signInRequired,
  notConfigured;

  String get message => switch (this) {
    disconnected => 'No saved account connection',
    checking => 'Renewing connection…',
    available => 'Session available — renews automatically',
    retrying => 'Connection unavailable — retrying automatically',
    signInRequired => 'Sign-in required — reconnect this account',
    notConfigured => 'Provider configuration needs attention',
  };
}

class CloudConnectionException implements Exception {
  final String message;
  final bool requiresSignIn;
  const CloudConnectionException(this.message, {this.requiresSignIn = false});
  @override
  String toString() => message;
}

extension _CloudSessionRenewal on CloudOAuthService {
  // Reserve the entire file lookup/read/decrypt or write/delete operation.
  // Merely waiting for prior writes lets a later write interrupt an active read.
  // Network work stays outside this queue; queued operations must not nest it.
  Future<T> _serializeAccountStorage<T>(
    String provider,
    Future<T> Function() action,
  ) {
    final result = (_storageOperations[provider] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final completion = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _storageOperations[provider] = completion;
    return result;
  }

  void _setConnectionStatus(String provider, CloudConnectionStatus status) {
    if (_states[provider] == status) return;
    _states[provider] = status;
    connectionStates.value = Map.unmodifiable(_states);
  }

  Future<CloudAuthorizedSession?> _authorizeWithRenewal(String providerId) {
    final pending = _pending[providerId];
    if (pending != null) return pending;
    final operation = _renewSavedConnection(
      providerId,
      _epochs[providerId] ?? 0,
    );
    _pending[providerId] = operation;
    void finished() {
      if (identical(_pending[providerId], operation)) {
        _pending.remove(providerId);
      }
    }

    operation.then<void>(
      (_) => finished(),
      onError: (Object _, StackTrace __) => finished(),
    );
    return operation;
  }

  Future<CloudAuthorizedSession?> _renewSavedConnection(
    String providerId,
    int epoch,
  ) async {
    bool current() => (_epochs[providerId] ?? 0) == epoch;
    final retry = _retry.putIfAbsent(providerId, ConnectionRetryGate.new);
    if (!retry.canAttempt(_now().toUtc())) {
      throw CloudConnectionException(
        (_states[providerId] ?? CloudConnectionStatus.retrying).message,
        requiresSignIn:
            _states[providerId] == CloudConnectionStatus.signInRequired,
      );
    }
    try {
      if (!current()) return null;
      final decoded = await _loadEncryptedAccountPayload(providerId);
      if (!current()) return null;
      if (decoded == null) {
        _setConnectionStatus(providerId, CloudConnectionStatus.disconnected);
        return null;
      }
      final accountJson = decoded['account'];
      final tokenJson = decoded['token'];
      if (accountJson is! Map<String, dynamic> ||
          tokenJson is! Map<String, dynamic>) {
        throw const CloudConnectionException(
          'Reconnect this saved account.',
          requiresSignIn: true,
        );
      }
      var account = CloudAccountInfo.fromJson(accountJson);
      if (account == null || account.providerId != providerId) {
        throw const CloudConnectionException(
          'Reconnect this saved account.',
          requiresSignIn: true,
        );
      }
      var token = Map<String, dynamic>.from(tokenJson);
      if (_tokenExpired(account) ||
          (token['access_token']?.toString().isEmpty ?? true)) {
        final refresh = token['refresh_token']?.toString().trim() ?? '';
        if (refresh.isEmpty) {
          throw const CloudConnectionException(
            'Sign in again to renew this account.',
            requiresSignIn: true,
          );
        }
        final provider =
            CloudConnectionStore.providers
                .where((p) => p.id == providerId)
                .firstOrNull;
        final config = provider == null ? null : _oauthConfigFor(provider);
        if (config == null ||
            config.clientId.isEmpty ||
            config.credentialIssue != null) {
          throw const _CloudOAuthTokenException(
            'Provider configuration needs attention.',
            isCredentialConfigurationIssue: true,
          );
        }
        _setConnectionStatus(providerId, CloudConnectionStatus.checking);
        token = await _refreshToken(
          config: config,
          refreshToken: refresh,
          previousPayload: token,
        );
        if (!current()) return null;
        account = CloudAccountInfo(
          providerId: account.providerId,
          providerLabel: account.providerLabel,
          accountLabel: account.accountLabel,
          connectedAtIso: account.connectedAtIso,
          expiresAtIso: _expiresAtIso(token),
        );
        await _saveEncryptedAccount(providerId, account, token, epoch: epoch);
      }
      if (!current()) return null;
      retry.succeeded();
      _setConnectionStatus(providerId, CloudConnectionStatus.available);
      return CloudAuthorizedSession(
        account: account,
        accessToken: token['access_token'].toString(),
      );
    } catch (error) {
      if (!current()) return null;
      final needsSignIn =
          error is CloudConnectionException && error.requiresSignIn;
      final configError =
          error is _CloudOAuthTokenException &&
          error.isCredentialConfigurationIssue;
      retry.failed(_now().toUtc(), requiresSignIn: needsSignIn || configError);
      _setConnectionStatus(
        providerId,
        needsSignIn
            ? CloudConnectionStatus.signInRequired
            : configError
            ? CloudConnectionStatus.notConfigured
            : CloudConnectionStatus.retrying,
      );
      // Never expose provider response bodies or tokens in diagnostics.
      throw CloudConnectionException(
        _states[providerId]!.message,
        requiresSignIn: needsSignIn,
      );
    }
  }
}
