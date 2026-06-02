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

bool get isLocalProLicenseActivationConfigured =>
    autoTeleprompterProLicenseHash.trim().isNotEmpty;

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
    final isPro = prefs.getBool(_proKey) ?? false;
    final licenseKey = prefs.getString(_licenseKey);

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

    if (isAdmin) {
      await _activatePro('build-admin');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_proKey);
    await prefs.remove(_licenseKey);
    state = AuthState();
  }

  Future<bool> activateLicense(String key) async {
    final expectedHash = autoTeleprompterProLicenseHash.trim().toLowerCase();
    final normalizedKey = key.trim();
    if (expectedHash.isEmpty || normalizedKey.isEmpty) return false;
    final actualHash = sha256.convert(utf8.encode(normalizedKey)).toString();
    if (actualHash.toLowerCase() != expectedHash) return false;
    await _activatePro('verified-local-license');
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
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
