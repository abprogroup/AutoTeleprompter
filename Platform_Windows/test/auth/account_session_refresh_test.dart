import 'dart:async';
import 'dart:io';

import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_models.dart';
import 'package:autoteleprompter/features/auth/services/account_grace_token.dart';
import 'package:autoteleprompter/features/auth/services/account_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = AccountBackendConfig(
    enabled: true,
    supabaseUrl: 'https://example.invalid',
    anonKey: 'test-public-key',
  );
  late MemorySessionStore store;
  late FakeAccountBackend backend;
  late AccountSessionManager manager;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = MemorySessionStore(savedSession());
    backend = FakeAccountBackend();
    manager = AccountSessionManager(backend: backend, store: store);
  });

  AuthNotifier notifier({AccountGraceTokenVerifier? grace}) {
    final result = AuthNotifier(
      accountBackendConfig: config,
      accountBackendService: backend,
      accountSessionStore: store,
      graceTokenVerifier: grace ?? const AccountGraceTokenVerifier(),
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    '22-day-old access token renews and persists rotated credentials',
    () async {
      final result = await manager.validSession();
      expect(backend.renewals, 1);
      expect(result.accessToken, 'new-access-1');
      expect(store.value!.refreshToken, 'rotated-refresh-1');
      expect(store.value!.deviceId, 'test-device');
    },
  );

  test('fresh session makes no token request', () async {
    store.value = savedSession(expired: false);
    await manager.validSession();
    expect(backend.renewals, 0);
  });

  test('near expiry renews before expiration', () async {
    store.value = savedSession(
      expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 90)),
    );
    await manager.validSession();
    expect(backend.renewals, 1);
  });

  test(
    'one rejected access token refreshes and retries profile exactly once',
    () async {
      store.value = savedSession(expired: false);
      backend.profileError = const AccountBackendError(
        'bad_jwt',
        'rejected',
        statusCode: 401,
      );
      backend.profileErrorCount = 1;
      final auth = notifier();
      await auth.initialized;
      expect(backend.renewals, 1);
      expect(backend.profiles, 2);
      expect(auth.state.backendStatus, 'active');
    },
  );

  test('persistent profile rejection does not start a refresh loop', () async {
    store.value = savedSession(expired: false);
    backend.profileError = const AccountBackendError(
      'bad_jwt',
      'rejected',
      statusCode: 401,
    );
    final auth = notifier();
    await auth.initialized;
    await auth.maintainConnection();
    expect(backend.renewals, 1);
    expect(backend.profiles, 2);
    expect(auth.state.backendStatus, 'sessionExpired');
  });

  test(
    'routine refresh does not interrupt still-valid verified access',
    () async {
      final auth = notifier();
      await auth.initialized;
      backend.profileBarrier = Completer<void>();
      final pending = auth.refreshBackendAccount();
      await until(() => backend.profiles == 2);
      expect(auth.state.hasPremiumAccess, isTrue);
      backend.profileBarrier!.complete();
      await pending;
    },
  );

  test('logout cancels a delayed explicit sign-in response', () async {
    store.value = null;
    final auth = notifier();
    await auth.initialized;
    backend.signInBarrier = Completer<void>();
    final pending = auth.signInWithBackendPassword(
      email: 'test@example.invalid',
      password: 'test-password',
    );
    await auth.logout();
    backend.signInBarrier!.complete();
    expect(await pending, isFalse);
    expect(auth.state.isSignedIn, isFalse);
    expect(store.value, isNull);
  });

  test('verified access expires even during retry backoff', () async {
    backend.renewalError = const SocketException('offline');
    final auth = notifier();
    await auth.initialized;
    await auth.applyBackendProfile(
      const AccountBackendProfile(
        accountId: 'user-test',
        email: 'test@example.invalid',
        status: 'active',
        role: AccountBackendRole.pro,
      ),
      tokenExpiry: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    await auth.maintainConnection();
    expect(auth.state.isPro, isFalse);
    expect(auth.state.isAdmin, isFalse);
    expect(backend.renewals, 1);
  });

  test('parallel callers share one renewal', () async {
    backend.renewalBarrier = Completer<void>();
    final requests = List.generate(8, (_) => manager.validSession());
    await until(() => backend.renewals == 1);
    backend.renewalBarrier!.complete();
    await Future.wait(requests);
    expect(backend.renewals, 1);
    expect(store.saved, hasLength(1));
  });

  test('offline renewal retains credentials', () async {
    backend.renewalError = const SocketException('offline');
    await expectLater(manager.validSession(), throwsA(isA<SocketException>()));
    expect(store.value!.refreshToken, 'saved-refresh');
    expect(store.clears, 0);
  });

  test('logout defeats a late renewal response', () async {
    backend.renewalBarrier = Completer<void>();
    final pending = manager.validSession();
    final assertion = expectLater(pending, throwsA(isA<AccountBackendError>()));
    await until(() => backend.renewals == 1);
    await manager.clear();
    backend.renewalBarrier!.complete();
    await assertion;
    expect(store.value, isNull);
    expect(store.saved, isEmpty);
  });

  test('wrong user identity cannot replace saved session', () async {
    backend.renewedUserId = 'different-user';
    await expectLater(
      manager.validSession(),
      throwsA(
        predicate(
          (e) =>
              e is AccountBackendError && e.code == 'session_identity_changed',
        ),
      ),
    );
    expect(store.value!.userId, 'user-test');
  });

  test('startup refreshes expired access BEFORE requesting profile', () async {
    final auth = notifier();
    await auth.initialized;
    expect(backend.renewals, 1);
    expect(backend.lastProfileToken, 'new-access-1');
    expect(auth.state.backendStatus, 'active');
    expect(auth.state.hasPremiumAccess, isTrue);
  });

  test('rotated token survives failure in subsequent profile check', () async {
    backend.profileError = const SocketException('offline after rotation');
    final auth = notifier();
    await auth.initialized;
    expect(store.value!.refreshToken, 'rotated-refresh-1');
    expect(store.clears, 0);
    expect(auth.state.hasPremiumAccess, isFalse);
    expect(auth.state.backendStatus, 'connectionRetryWaiting');
    backend.profileError = null;
    await auth.refreshBackendAccount();
    expect(auth.state.backendStatus, 'active');
    expect(auth.state.backendError, isNull);
    expect(backend.renewals, 1);
  });

  test(
    'network failure retries later without busy looping or deleting login',
    () async {
      backend.renewalError = const SocketException('offline');
      final auth = notifier();
      await auth.initialized;
      await auth.maintainConnection();
      await auth.maintainConnection();
      expect(backend.renewals, 1);
      expect(store.clears, 0);
      expect(auth.state.isPro, isFalse);
    },
  );

  test('revoked refresh cannot use offline grace or cached Pro', () async {
    backend.renewalError = const AccountBackendError(
      'invalid_grant',
      'revoked',
      statusCode: 400,
    );
    final grace = _GraceSpy();
    final auth = notifier(grace: grace);
    await auth.initialized;
    expect(auth.state.isSignedIn, isFalse);
    expect(auth.state.isPro, isFalse);
    expect(auth.state.backendStatus, 'sessionExpired');
    expect(store.value, isNull);
    expect(grace.calls, 0);
  });

  test('disabled profile cannot use signed grace', () async {
    backend.profileError = const AccountBackendError(
      'account_disabled',
      'disabled',
      statusCode: 403,
    );
    final grace = _GraceSpy();
    final auth = notifier(grace: grace);
    await auth.initialized;
    expect(auth.state.backendStatus, 'disabledAccount');
    expect(auth.state.hasPremiumAccess, isFalse);
    expect(grace.calls, 0);
  });

  test('logout while profile is loading cannot restore login', () async {
    backend.profileBarrier = Completer<void>();
    final auth = notifier();
    await until(() => backend.profiles == 1);
    await auth.logout();
    backend.profileBarrier!.complete();
    await auth.initialized;
    expect(store.value, isNull);
    expect(auth.state.isSignedIn, isFalse);
  });

  test(
    'clock rollback blocks renewal without deleting saved connection',
    () async {
      store.value = savedSession(
        lastServerTimestamp: DateTime.now().toUtc().add(
          const Duration(days: 1),
        ),
      );
      final auth = notifier();
      await auth.initialized;
      expect(auth.state.backendStatus, 'clockRollbackDetected');
      expect(backend.renewals, 0);
      expect(store.value, isNotNull);
      expect(auth.state.isPro, isFalse);
    },
  );

  test('remember-me off still clears session at next startup', () async {
    SharedPreferences.setMockInitialValues({'auth_backend_remember_me': false});
    final auth = notifier();
    await auth.initialized;
    expect(store.value, isNull);
    expect(backend.renewals, 0);
  });

  test(
    'missing refresh asks for login rather than submitting expired access',
    () async {
      store.value = savedSession(refresh: null);
      final auth = notifier();
      await auth.initialized;
      expect(auth.state.backendStatus, 'sessionExpired');
      expect(backend.profiles, 0);
    },
  );
}

class _GraceSpy extends AccountGraceTokenVerifier {
  int calls = 0;
  @override
  AccountGracePayload? verify(
    String? token, {
    required String expectedDeviceId,
    DateTime? lastServerTimestamp,
    DateTime? now,
  }) {
    calls++;
    return null;
  }
}
