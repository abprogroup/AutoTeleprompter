import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  AuthState({
    this.email,
    this.isPro = false,
    this.isAdmin = false,
    this.licenseKey,
  });

  bool get isSignedIn => email != null && email!.trim().isNotEmpty;

  bool get hasPremiumAccess => isSignedIn && isPro;

  AuthState copyWith({
    String? email,
    bool? isPro,
    bool? isAdmin,
    String? licenseKey,
  }) {
    return AuthState(
      email: email ?? this.email,
      isPro: isPro ?? this.isPro,
      isAdmin: isAdmin ?? this.isAdmin,
      licenseKey: licenseKey ?? this.licenseKey,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  static const _emailKey = 'auth_email';
  static const _proKey = 'auth_is_pro';
  static const _licenseKey = 'auth_license_key';

  AuthNotifier() : super(AuthState()) {
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    var isPro = prefs.getBool(_proKey) ?? false;
    var licenseKey = prefs.getString(_licenseKey);
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
    );
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_proKey);
    await prefs.remove(_licenseKey);
    state = AuthState();
  }

  Future<bool> activateLicense(String key) async {
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
