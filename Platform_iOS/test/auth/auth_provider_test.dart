import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_models.dart';
import 'package:autoteleprompter/features/auth/services/account_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AuthNotifier backend mode', () {
    test('clears local fallback Pro state when backend is enabled', () async {
      SharedPreferences.setMockInitialValues({
        'auth_email': 'legacy@example.com',
        'auth_is_pro': true,
        'auth_license_key': 'verified-pro-license',
      });

      final notifier = AuthNotifier(
        accountBackendConfig: const AccountBackendConfig(enabled: true),
        accountSessionStore: _MemoryAccountSessionStore(),
      );

      await pumpEventQueue(times: 5);

      expect(notifier.state.accountBackendEnabled, isTrue);
      expect(notifier.state.backendStatus, 'notConfigured');
      expect(notifier.state.email, isNull);
      expect(notifier.state.isPro, isFalse);
      expect(notifier.state.licenseKey, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_email'), isNull);
      expect(prefs.getBool('auth_is_pro'), isNull);
      expect(prefs.getString('auth_license_key'), isNull);
    });

    test('refuses local license activation in backend-enabled builds',
        () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = AuthNotifier(
        accountBackendConfig: _configuredBackend,
        accountSessionStore: _MemoryAccountSessionStore(),
      );

      await pumpEventQueue(times: 5);

      expect(await notifier.activateLicense('PRO-anything'), isFalse);
      expect(notifier.state.isPro, isFalse);
      expect(notifier.state.licenseKey, isNull);
    });

    test('applies backend Pro and Admin profile state', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = AuthNotifier(
        accountBackendConfig: _configuredBackend,
        accountSessionStore: _MemoryAccountSessionStore(),
      );

      await pumpEventQueue(times: 5);

      await notifier.applyBackendProfile(
        const AccountBackendProfile(
          accountId: 'account-pro',
          email: 'pro@example.com',
          status: 'active',
          role: AccountBackendRole.pro,
        ),
        deviceId: 'ios-device',
      );

      expect(notifier.state.email, 'pro@example.com');
      expect(notifier.state.backendStatus, 'active');
      expect(notifier.state.roleLabel, 'Pro');
      expect(notifier.state.hasPremiumAccess, isTrue);
      expect(notifier.state.isAdmin, isFalse);

      await notifier.applyBackendProfile(
        const AccountBackendProfile(
          accountId: 'account-admin',
          email: 'admin@example.com',
          status: 'active',
          role: AccountBackendRole.admin,
        ),
        deviceId: 'ios-device',
      );

      expect(notifier.state.email, 'admin@example.com');
      expect(notifier.state.roleLabel, 'Admin');
      expect(notifier.state.hasPremiumAccess, isTrue);
      expect(notifier.state.isAdmin, isTrue);
    });
  });
}

const _configuredBackend = AccountBackendConfig(
  enabled: true,
  supabaseUrl: 'https://example.supabase.co',
  anonKey: 'anon-key',
);

class _MemoryAccountSessionStore extends AccountSessionStore {
  AccountSessionSnapshot? snapshot;

  @override
  Future<void> save(AccountSessionSnapshot snapshot) async {
    this.snapshot = snapshot;
  }

  @override
  Future<AccountSessionSnapshot?> read() async => snapshot;

  @override
  Future<void> clear() async {
    snapshot = null;
  }
}
