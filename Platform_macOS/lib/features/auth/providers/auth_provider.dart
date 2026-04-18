import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _adminEmail = 'abmpro.office@gmail.com';

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
      isAdmin: email == _adminEmail,
      licenseKey: licenseKey,
    );
  }

  Future<void> login(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
    
    state = state.copyWith(
      email: email,
      isAdmin: email == _adminEmail,
    );
    
    // Auto-activate Pro for Admin
    if (state.isAdmin) {
      await activateLicense('PRO-ADMIN-V3');
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
    // Professional license key check (MOCK)
    if (key.startsWith('PRO-') || state.isAdmin) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_proKey, true);
      await prefs.setString(_licenseKey, key);
      state = state.copyWith(isPro: true, licenseKey: key);
      return true;
    }
    return false;
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
