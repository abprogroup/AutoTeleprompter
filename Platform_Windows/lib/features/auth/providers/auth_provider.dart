import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/account_backend_service.dart';
import '../services/account_backend_config.dart';
import '../services/account_backend_models.dart';
import '../services/account_session_store.dart';

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

class AuthState {
  final String? email;
  final bool isPro;
  final bool isAdmin;
  final String? licenseKey;
  final bool accountBackendEnabled;
  final String? backendAccountId;
  final AccountBackendRole backendRole;
  final String backendStatus;
  final String? backendError;
  final DateTime? backendTokenExpiry;
  final DateTime? offlineGraceExpiry;
  final String? deviceId;
  final DateTime? lastServerTimestamp;

  AuthState({
    this.email,
    this.isPro = false,
    this.isAdmin = false,
    this.licenseKey,
    this.accountBackendEnabled = false,
    this.backendAccountId,
    this.backendRole = AccountBackendRole.free,
    this.backendStatus = 'disabled',
    this.backendError,
    this.backendTokenExpiry,
    this.offlineGraceExpiry,
    this.deviceId,
    this.lastServerTimestamp,
  });

  bool get isSignedIn => email != null && email!.trim().isNotEmpty;

  bool get hasPremiumAccess => isSignedIn && isPro;

  bool get isBackendActive =>
      accountBackendEnabled && backendStatus == 'active';

  bool get isCheckingBackendAccess =>
      accountBackendEnabled &&
      const {
        'storedSession',
        'refreshingStoredSession',
        'requestingCode',
        'verifyingCode',
      }.contains(backendStatus);

  AuthState copyWith({
    String? email,
    bool? isPro,
    bool? isAdmin,
    String? licenseKey,
    bool? accountBackendEnabled,
    String? backendAccountId,
    AccountBackendRole? backendRole,
    String? backendStatus,
    String? backendError,
    DateTime? backendTokenExpiry,
    DateTime? offlineGraceExpiry,
    String? deviceId,
    DateTime? lastServerTimestamp,
  }) {
    return AuthState(
      email: email ?? this.email,
      isPro: isPro ?? this.isPro,
      isAdmin: isAdmin ?? this.isAdmin,
      licenseKey: licenseKey ?? this.licenseKey,
      accountBackendEnabled:
          accountBackendEnabled ?? this.accountBackendEnabled,
      backendAccountId: backendAccountId ?? this.backendAccountId,
      backendRole: backendRole ?? this.backendRole,
      backendStatus: backendStatus ?? this.backendStatus,
      backendError: backendError ?? this.backendError,
      backendTokenExpiry: backendTokenExpiry ?? this.backendTokenExpiry,
      offlineGraceExpiry: offlineGraceExpiry ?? this.offlineGraceExpiry,
      deviceId: deviceId ?? this.deviceId,
      lastServerTimestamp: lastServerTimestamp ?? this.lastServerTimestamp,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  static const _emailKey = 'auth_email';
  static const _proKey = 'auth_is_pro';
  static const _licenseKey = 'auth_license_key';
  static const _backendDeviceKey = 'auth_backend_device_id';

  AuthNotifier({
    AccountBackendConfig accountBackendConfig = const AccountBackendConfig(),
    AccountBackendService? accountBackendService,
    AccountSessionStore? accountSessionStore,
  })  : _accountBackendConfig = accountBackendConfig,
        _accountBackendService = accountBackendService ??
            AccountBackendService(config: accountBackendConfig),
        _accountSessionStore = accountSessionStore ?? AccountSessionStore(),
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

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accountBackendConfig.enabled) {
      await prefs.remove(_emailKey);
      await prefs.remove(_proKey);
      await prefs.remove(_licenseKey);
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
      final deviceId = await _ensureBackendDeviceId();
      final profile = await _accountBackendService.refreshSession(
        accessToken: session.accessToken,
        deviceId: deviceId,
        friendlyName: 'Windows',
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
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _emailKey,
        profile.email.isNotEmpty ? profile.email : normalizedEmail,
      );
      await applyBackendProfile(
        profile,
        deviceId: deviceId,
        tokenExpiry: session.expiresAt,
      );
      return profile.hasPremiumAccess || profile.isAdmin;
    } catch (error) {
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'codeVerifyFailed',
        backendError: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_proKey);
    await prefs.remove(_licenseKey);
    await _accountSessionStore.clear();
    state = AuthState(
      accountBackendEnabled: _accountBackendConfig.enabled,
      backendStatus: _accountBackendConfig.isConfigured
          ? 'signedOut'
          : _accountBackendConfig.enabled
              ? 'notConfigured'
              : 'disabled',
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
      deviceId: deviceId,
      lastServerTimestamp: profile.serverTime,
    );
  }

  Future<void> _loadStoredBackendSession() async {
    if (!_accountBackendConfig.isConfigured) return;
    try {
      final session = await _accountSessionStore.read();
      if (session == null || session.accessToken.trim().isEmpty) return;
      final now = DateTime.now().toUtc();
      final lastServerTimestamp = session.lastServerTimestamp;
      if (lastServerTimestamp != null &&
          now.isBefore(lastServerTimestamp.subtract(const Duration(minutes: 5)))) {
        await _accountSessionStore.clear();
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
        await _accountSessionStore.clear();
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
      final deviceId = session.deviceId ?? await _ensureBackendDeviceId();
      final profile = await _accountBackendService.refreshSession(
        accessToken: session.accessToken,
        deviceId: deviceId,
        friendlyName: 'Windows',
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
        ),
      );
      await applyBackendProfile(
        profile,
        deviceId: deviceId,
        tokenExpiry: session.expiresAt,
      );
    } catch (error) {
      await _accountSessionStore.clear();
      state = state.copyWith(
        accountBackendEnabled: true,
        backendStatus: 'sessionRefreshFailed',
        backendError: error.toString(),
        isPro: false,
        isAdmin: false,
      );
    }
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
    return 'windows-$encoded';
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
