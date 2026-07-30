import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_backend_service.dart';
import '../services/account_backend_config.dart';
import '../services/account_grace_token.dart';
import '../services/account_backend_models.dart';
import '../services/account_session_store.dart';

part 'auth_provider.state.dart';

const autoTeleprompterAdminEmail = String.fromEnvironment(
  'AUTOTELEPROMPTER_ADMIN_EMAIL',
);
const autoTeleprompterProLicenseHash = String.fromEnvironment(
  'AUTOTELEPROMPTER_PRO_LICENSE_SHA256',
);
const autoTeleprompterAdminCodeHash = String.fromEnvironment(
  'AUTOTELEPROMPTER_ADMIN_CODE_SHA256',
);

bool get isLocalProLicenseActivationConfigured =>
    autoTeleprompterProLicenseHash.trim().isNotEmpty ||
    autoTeleprompterAdminCodeHash.trim().isNotEmpty;

class AuthNotifier extends StateNotifier<AuthState> {
  static const _emailKey = 'auth_email';
  static const _proKey = 'auth_is_pro';
  static const _licenseKey = 'auth_license_key';
  static const _backendDeviceKey = 'auth_backend_device_id';
  static const _backendRememberMeKey = 'auth_backend_remember_me';
  static const _backendLastEmailKey = 'auth_backend_last_email';

  AuthNotifier({
    AccountBackendConfig accountBackendConfig = const AccountBackendConfig(),
    AccountBackendService? accountBackendService,
    AccountSessionStore? accountSessionStore,
    AccountGraceTokenVerifier graceTokenVerifier =
        const AccountGraceTokenVerifier(),
  })  : _accountBackendConfig = accountBackendConfig,
        _accountBackendService = accountBackendService ??
            AccountBackendService(config: accountBackendConfig),
        _accountSessionStore = accountSessionStore ?? AccountSessionStore(),
        _graceTokenVerifier = graceTokenVerifier,
        super(
          AuthState(
            accountBackendEnabled: accountBackendConfig.enabled,
            backendStatus: accountBackendConfig.isConfigured
                ? 'available'
                : accountBackendConfig.enabled
                    ? 'notConfigured'
                    : 'disabled',
          ),
        ) {
    _loadState();
  }

  final AccountBackendConfig _accountBackendConfig;
  final AccountBackendService _accountBackendService;
  final AccountSessionStore _accountSessionStore;
  final AccountGraceTokenVerifier _graceTokenVerifier;

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_backendRememberMeKey) ?? true;
    final lastEmailUsed = prefs.getString(_backendLastEmailKey);
    if (_accountBackendConfig.enabled) {
      await prefs.remove(_emailKey);
      await prefs.remove(_proKey);
      await prefs.remove(_licenseKey);
      if (!rememberMe) await _clearStoredBackendSession();
    }
    final email =
        _accountBackendConfig.enabled ? null : prefs.getString(_emailKey);
    var isPro = prefs.getBool(_proKey) ?? false;
    var licenseKey = prefs.getString(_licenseKey);
    if (_accountBackendConfig.enabled) {
      isPro = false;
      licenseKey = null;
    }
    if (licenseKey == 'build-admin' &&
        autoTeleprompterAdminCodeHash.trim().isNotEmpty) {
      await prefs.remove(_proKey);
      await prefs.remove(_licenseKey);
      isPro = false;
      licenseKey = null;
    }

    state = AuthState(
      email: email,
      isPro: isPro,
      isAdmin: _isAdminEmail(email),
      licenseKey: licenseKey,
      accountBackendEnabled: _accountBackendConfig.enabled,
      backendStatus: _accountBackendConfig.isConfigured
          ? 'available'
          : _accountBackendConfig.enabled
              ? 'notConfigured'
              : 'disabled',
      rememberMe: rememberMe,
      lastEmailUsed: lastEmailUsed,
    );
    await _loadStoredBackendSession();
  }

  Future<void> login(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim();
    await prefs.setString(_emailKey, normalizedEmail);

    final isAdmin = _isAdminEmail(normalizedEmail);
    state = state.copyWith(
      email: normalizedEmail,
      isAdmin: isAdmin,
    );

    if (!isAdmin) return;
    if (autoTeleprompterAdminCodeHash.trim().isEmpty) return;
  }

  Future<void> requestBackendLoginCode(String email) async {
    if (!_accountBackendConfig.isConfigured) {
      throw const AccountBackendError(
        'backend_not_configured',
        'Account backend is not configured for this build.',
      );
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AccountBackendError(
        'missing_email',
        'Enter an email address before requesting a login code.',
      );
    }
    state = state.copyWith(
      accountBackendEnabled: true,
      backendStatus: 'requestingCode',
      backendError: null,
    );
    try {
      await _accountBackendService.requestLoginCode(normalizedEmail);
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'codeSent',
        backendError: null,
      );
    } catch (error) {
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'codeRequestFailed',
        backendError: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> setBackendRememberMe(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backendRememberMeKey, remember);
    state = state.copyWith(rememberMe: remember);
  }

  Future<bool> refreshBackendAccount() async {
    if (!_accountBackendConfig.isConfigured) {
      throw const AccountBackendError(
        'backend_not_configured',
        'Account backend is not configured for this build.',
      );
    }
    final session = await _requireStoredSession();
    final deviceId = session.deviceId ?? await _ensureBackendDeviceId();
    final profile = await _accountBackendService.refreshSession(
      accessToken: session.accessToken,
      deviceId: deviceId,
      friendlyName: 'Android',
    );
    await _saveBackendSessionSnapshot(session, profile, deviceId);
    await applyBackendProfile(
      profile,
      deviceId: deviceId,
      tokenExpiry: session.expiresAt,
    );
    return state.hasPremiumAccess || state.isAdmin;
  }

  Future<void> deleteBackendAccount({required String confirmation}) async {
    if (!_accountBackendConfig.isConfigured) {
      throw const AccountBackendError(
        'backend_not_configured',
        'Account backend is not configured for this build.',
      );
    }
    final session = await _requireStoredSession();
    await _accountBackendService.deleteAccount(
      accessToken: session.accessToken,
      confirmation: confirmation,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_proKey);
    await prefs.remove(_licenseKey);
    await prefs.remove(_backendLastEmailKey);
    await _clearStoredBackendSession();
    state = AuthState(
      accountBackendEnabled: _accountBackendConfig.enabled,
      backendStatus: _accountBackendConfig.isConfigured
          ? 'signedOut'
          : _accountBackendConfig.enabled
              ? 'notConfigured'
              : 'disabled',
      rememberMe: prefs.getBool(_backendRememberMeKey) ?? state.rememberMe,
    );
  }

  Future<bool> verifyBackendLoginCode({
    required String email,
    required String code,
  }) async {
    if (!_accountBackendConfig.isConfigured) {
      throw const AccountBackendError(
        'backend_not_configured',
        'Account backend is not configured for this build.',
      );
    }
    final normalizedEmail = email.trim();
    final normalizedCode = code.trim();
    if (normalizedEmail.isEmpty || normalizedCode.isEmpty) return false;
    state = state.copyWith(
      accountBackendEnabled: true,
      backendStatus: 'verifyingCode',
      backendError: null,
    );
    try {
      final session = await _accountBackendService.verifyLoginCode(
        email: normalizedEmail,
        code: normalizedCode,
      );
      return _activateBackendSession(
        session,
        fallbackEmail: normalizedEmail,
      );
    } catch (error) {
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'codeVerifyFailed',
        backendError: error.toString(),
      );
      rethrow;
    }
  }

  Future<bool> signInWithBackendPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    _validatePasswordInput(password);
    state = state.copyWith(
      accountBackendEnabled: true,
      backendStatus: 'passwordSignIn',
      backendError: null,
    );
    try {
      final session = await _accountBackendService.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      return _activateBackendSession(
        session,
        fallbackEmail: normalizedEmail,
      );
    } catch (error) {
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'passwordSignInFailed',
        backendError: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> setBackendPassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    _validatePasswordInput(newPassword);
    final session = await _requireStoredSession();
    final email = state.email?.trim();
    AccountBackendSession? refreshedSession;
    var accessTokenForUpdate = session.accessToken;
    if (currentPassword != null && currentPassword.trim().isNotEmpty) {
      if (email == null || email.isEmpty) {
        throw const AccountBackendError(
          'missing_email',
          'Current account email is missing.',
        );
      }
      refreshedSession = await _accountBackendService.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      accessTokenForUpdate = refreshedSession.accessToken;
    } else if (session.refreshToken != null &&
        session.refreshToken!.trim().isNotEmpty) {
      refreshedSession = await _accountBackendService.refreshAccessToken(
        refreshToken: session.refreshToken!,
      );
      accessTokenForUpdate = refreshedSession.accessToken;
    }
    await _accountBackendService.setPassword(
      accessToken: accessTokenForUpdate,
      password: newPassword,
    );
    if (refreshedSession != null) {
      await _activateBackendSession(
        refreshedSession,
        fallbackEmail: email ?? session.email ?? '',
      );
    }
  }

  Future<void> requestBackendPasswordResetCode(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AccountBackendError(
        'missing_email',
        'Enter an email address before requesting a password reset.',
      );
    }
    await _accountBackendService.requestPasswordResetCode(normalizedEmail);
  }

  Future<bool> resetBackendPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final normalizedEmail = email.trim();
    final normalizedCode = code.trim();
    if (normalizedEmail.isEmpty || normalizedCode.isEmpty) {
      throw const AccountBackendError(
        'missing_reset_code',
        'Email and reset code are required.',
      );
    }
    _validatePasswordInput(newPassword);
    final session = await _accountBackendService.verifyPasswordResetCode(
      email: normalizedEmail,
      code: normalizedCode,
    );
    await _accountBackendService.setPassword(
      accessToken: session.accessToken,
      password: newPassword,
    );
    return _activateBackendSession(
      session,
      fallbackEmail: normalizedEmail,
    );
  }

  Future<void> changeBackendEmailWithPassword({
    required String newEmail,
    required String currentPassword,
  }) async {
    final currentEmail = state.email?.trim();
    final normalizedNewEmail = newEmail.trim();
    _validatePasswordInput(currentPassword);
    if (currentEmail == null || currentEmail.isEmpty) {
      throw const AccountBackendError(
        'missing_email',
        'Current account email is missing.',
      );
    }
    if (normalizedNewEmail.isEmpty) {
      throw const AccountBackendError(
        'missing_new_email',
        'Enter the new email address.',
      );
    }
    final verifiedSession = await _accountBackendService.signInWithPassword(
      email: currentEmail,
      password: currentPassword,
    );
    await _accountBackendService.updateEmail(
      accessToken: verifiedSession.accessToken,
      newEmail: normalizedNewEmail,
    );
  }

  Future<bool> verifyBackendEmailChangeCode({
    required String newEmail,
    required String code,
  }) async {
    final normalizedNewEmail = newEmail.trim();
    final normalizedCode = code.trim();
    if (normalizedNewEmail.isEmpty || normalizedCode.isEmpty) {
      throw const AccountBackendError(
        'missing_email_change_code',
        'New email and confirmation code are required.',
      );
    }
    final session = await _accountBackendService.verifyEmailChangeCode(
      email: normalizedNewEmail,
      code: normalizedCode,
    );
    return _activateBackendSession(
      session,
      fallbackEmail: normalizedNewEmail,
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final lastEmail = state.email?.trim();
    if (lastEmail != null && lastEmail.isNotEmpty) {
      await prefs.setString(_backendLastEmailKey, lastEmail);
    }
    await prefs.remove(_emailKey);
    await prefs.remove(_proKey);
    await prefs.remove(_licenseKey);
    await _clearStoredBackendSession();
    state = AuthState(
      accountBackendEnabled: _accountBackendConfig.enabled,
      backendStatus: _accountBackendConfig.isConfigured
          ? 'signedOut'
          : _accountBackendConfig.enabled
              ? 'notConfigured'
              : 'disabled',
      rememberMe: prefs.getBool(_backendRememberMeKey) ?? state.rememberMe,
      lastEmailUsed: lastEmail ?? state.lastEmailUsed,
    );
  }

  Future<bool> activateLicense(String key) async {
    if (_accountBackendConfig.enabled) return false;
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return false;
    final actualHash = sha256.convert(utf8.encode(normalizedKey)).toString();
    if (state.isAdmin &&
        _hashMatches(actualHash, autoTeleprompterAdminCodeHash)) {
      await _activatePro('verified-admin-code');
      return true;
    }
    if (!_hashMatches(actualHash, autoTeleprompterProLicenseHash)) {
      return false;
    }
    await _activatePro('verified-pro-license');
    return true;
  }

  Future<void> _activatePro(String source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proKey, true);
    await prefs.setString(_licenseKey, source);
    state = state.copyWith(isPro: true, licenseKey: source);
  }

  Future<void> applyBackendProfile(
    AccountBackendProfile profile, {
    String? deviceId,
    DateTime? tokenExpiry,
  }) async {
    if (!_accountBackendConfig.isConfigured) return;
    final role = profile.role;
    final serverNow = profile.serverTime ?? DateTime.now().toUtc();
    state = state.copyWith(
      email: profile.email.isNotEmpty ? profile.email : state.email,
      isPro: profile.hasPremiumAccessAt(serverNow),
      isAdmin: profile.isAdminAt(serverNow),
      accountBackendEnabled: true,
      backendAccountId: profile.accountId,
      backendRole: role,
      backendStatus: profile.isDisabled ? 'disabledAccount' : 'active',
      backendError: null,
      backendTokenExpiry: tokenExpiry,
      backendEntitlementStatus: profile.entitlementStatus,
      entitlementExpiresAt: profile.entitlementExpiresAt,
      clearEntitlementExpiresAt: profile.entitlementExpiresAt == null,
      entitlementRevoked: profile.entitlementRevoked,
      offlineGraceExpiry: profile.graceExpiresAt,
      deviceId: deviceId,
      lastServerTimestamp: profile.serverTime,
      lastEmailUsed: profile.email.isNotEmpty ? profile.email : state.email,
    );
  }

  Future<bool> _activateBackendSession(
    AccountBackendSession session, {
    required String fallbackEmail,
  }) async {
    final deviceId = await _ensureBackendDeviceId();
    final profile = await _accountBackendService.refreshSession(
      accessToken: session.accessToken,
      deviceId: deviceId,
      friendlyName: 'Android',
    );
    await _accountSessionStore.save(
      AccountSessionSnapshot(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        userId:
            profile.accountId.isNotEmpty ? profile.accountId : session.userId,
        email: profile.email.isNotEmpty ? profile.email : session.email,
        deviceId: deviceId,
        role: profile.role,
        expiresAt: session.expiresAt,
        lastServerTimestamp: profile.serverTime,
        graceToken: profile.graceToken,
        graceExpiresAt: profile.graceExpiresAt,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    final resolvedEmail =
        profile.email.isNotEmpty ? profile.email : fallbackEmail;
    await prefs.setString(
      _emailKey,
      resolvedEmail,
    );
    if (resolvedEmail.trim().isNotEmpty) {
      await prefs.setString(_backendLastEmailKey, resolvedEmail.trim());
    }
    await applyBackendProfile(
      profile,
      deviceId: deviceId,
      tokenExpiry: session.expiresAt,
    );
    return profile.hasPremiumAccess || profile.isAdmin;
  }

  Future<void> _saveBackendSessionSnapshot(
    AccountSessionSnapshot session,
    AccountBackendProfile profile,
    String deviceId,
  ) async {
    await _accountSessionStore.save(
      AccountSessionSnapshot(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        userId:
            profile.accountId.isNotEmpty ? profile.accountId : session.userId,
        email: profile.email.isNotEmpty ? profile.email : session.email,
        deviceId: deviceId,
        role: profile.role,
        expiresAt: session.expiresAt,
        lastServerTimestamp: profile.serverTime,
        graceToken: profile.graceToken,
        graceExpiresAt: profile.graceExpiresAt,
      ),
    );
  }

  Future<AccountSessionSnapshot> _requireStoredSession() async {
    final session = await _accountSessionStore.read();
    if (session == null || session.accessToken.trim().isEmpty) {
      throw const AccountBackendError(
        'signed_out',
        'Sign in before changing account security settings.',
      );
    }
    return session;
  }

  Future<void> _clearStoredBackendSession() async {
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await _accountSessionStore.clear();
        return;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    if (lastError != null) throw lastError;
  }

  void _validatePasswordInput(String password) {
    if (password.length < 8) {
      throw const AccountBackendError(
        'weak_password',
        'Password must be at least 8 characters.',
      );
    }
  }

  Future<void> _loadStoredBackendSession() async {
    if (!_accountBackendConfig.isConfigured) return;
    AccountSessionSnapshot? session;
    String? deviceId;
    try {
      session = await _accountSessionStore.read();
      if (!mounted) return;
      if (session == null || session.accessToken.trim().isEmpty) return;
      final now = DateTime.now().toUtc();
      final lastServerTimestamp = session.lastServerTimestamp;
      if (lastServerTimestamp != null &&
          now.isBefore(
              lastServerTimestamp.subtract(const Duration(minutes: 5)))) {
        await _clearStoredBackendSession();
        state = state.copyWith(
          accountBackendEnabled: true,
          backendStatus: 'clockRollbackDetected',
          backendError:
              'Local clock is earlier than the last verified server time.',
          isPro: false,
          isAdmin: false,
        );
        return;
      }
      if (session.expiresAt != null && !session.expiresAt!.isAfter(now)) {
        deviceId = session.deviceId ?? await _ensureBackendDeviceId();
        if (_applyOfflineGrace(session, deviceId)) return;
        await _clearStoredBackendSession();
        state = state.copyWith(
          accountBackendEnabled: true,
          backendStatus: 'sessionExpired',
          backendError: 'Account session expired. Sign in again.',
          isPro: false,
          isAdmin: false,
        );
        return;
      }
      state = state.copyWith(
        accountBackendEnabled: true,
        backendAccountId: session.userId,
        backendRole: session.role,
        backendStatus: 'refreshingStoredSession',
        backendTokenExpiry: session.expiresAt,
        deviceId: session.deviceId,
        lastServerTimestamp: session.lastServerTimestamp,
        email: session.email,
        isPro: false,
        isAdmin: false,
      );
      deviceId = session.deviceId ?? await _ensureBackendDeviceId();
      if (!mounted) return;
      final profile = await _accountBackendService.refreshSession(
        accessToken: session.accessToken,
        deviceId: deviceId,
        friendlyName: 'Android',
      );
      if (!mounted) return;
      await _accountSessionStore.save(
        AccountSessionSnapshot(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          userId:
              profile.accountId.isNotEmpty ? profile.accountId : session.userId,
          email: profile.email.isNotEmpty ? profile.email : session.email,
          deviceId: deviceId,
          role: profile.role,
          expiresAt: session.expiresAt,
          lastServerTimestamp: profile.serverTime,
          graceToken: profile.graceToken,
          graceExpiresAt: profile.graceExpiresAt,
        ),
      );
      await applyBackendProfile(
        profile,
        deviceId: deviceId,
        tokenExpiry: session.expiresAt,
      );
    } catch (error) {
      if (!mounted) return;
      if (_applyOfflineGrace(session, deviceId ?? session?.deviceId)) return;
      await _clearStoredBackendSession();
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'sessionRefreshFailed',
        backendError: error.toString(),
        isPro: false,
        isAdmin: false,
      );
    }
  }

  bool _applyOfflineGrace(
    AccountSessionSnapshot? session,
    String? deviceId,
  ) {
    if (session == null || deviceId == null || deviceId.trim().isEmpty) {
      return false;
    }
    final grace = _graceTokenVerifier.verify(
      session.graceToken,
      expectedDeviceId: deviceId,
      lastServerTimestamp: session.lastServerTimestamp,
    );
    if (grace == null) return false;
    final now = DateTime.now().toUtc();
    state = state.copyWith(
      email: grace.email.isNotEmpty ? grace.email : session.email,
      isPro: grace.hasPremiumAccessAt(now),
      isAdmin: grace.isAdminAt(now),
      accountBackendEnabled: true,
      backendAccountId:
          grace.accountId.isNotEmpty ? grace.accountId : session.userId,
      backendRole: grace.role,
      backendStatus: 'offlineGraceActive',
      backendError: null,
      backendEntitlementStatus: grace.status,
      entitlementExpiresAt: grace.entitlementExpiresAt,
      clearEntitlementExpiresAt: grace.entitlementExpiresAt == null,
      entitlementRevoked: false,
      offlineGraceExpiry: grace.expiresAt,
      deviceId: deviceId,
      lastServerTimestamp: session.lastServerTimestamp,
      lastEmailUsed: grace.email.isNotEmpty ? grace.email : session.email,
    );
    return state.hasPremiumAccess || state.isAdmin;
  }

  Future<String> _ensureBackendDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_backendDeviceKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = _newBackendDeviceId();
    await prefs.setString(_backendDeviceKey, id);
    return id;
  }

  String _newBackendDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    return 'android-$encoded';
  }

  bool _isAdminEmail(String? email) {
    final configured = autoTeleprompterAdminEmail.trim().toLowerCase();
    final candidate = (email ?? '').trim().toLowerCase();
    return configured.isNotEmpty && candidate == configured;
  }

  bool _hashMatches(String actualHash, String expectedHash) {
    final expected = expectedHash.trim().toLowerCase();
    return expected.isNotEmpty && actualHash.toLowerCase() == expected;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
