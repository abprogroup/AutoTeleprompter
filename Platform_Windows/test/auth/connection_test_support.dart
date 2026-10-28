import 'dart:async';

import 'package:autoteleprompter/features/auth/services/account_backend_models.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_service.dart';
import 'package:autoteleprompter/features/auth/services/account_session_store.dart';

class MemorySessionStore extends AccountSessionStore {
  AccountSessionSnapshot? value;
  int clears = 0;
  final saved = <AccountSessionSnapshot>[];
  MemorySessionStore(this.value);
  @override
  Future<AccountSessionSnapshot?> read() async => value;
  @override
  Future<void> save(AccountSessionSnapshot snapshot) async {
    saved.add(snapshot);
    value = snapshot;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class FakeAccountBackend extends AccountBackendService {
  int renewals = 0;
  int profiles = 0;
  Object? renewalError;
  Object? profileError;
  int? profileErrorCount;
  Completer<void>? signInBarrier;
  Completer<void>? renewalBarrier;
  Completer<void>? profileBarrier;
  String lastProfileToken = '';
  final refreshTokens = <String>[];
  String renewedUserId = 'user-test';
  @override
  Future<AccountBackendSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await signInBarrier?.future;
    return AccountBackendSession(
      accessToken: 'signed-in-access',
      refreshToken: 'signed-in-refresh',
      userId: 'user-test',
      email: email,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<AccountBackendSession> refreshAccessToken({
    required String refreshToken,
  }) async {
    renewals++;
    refreshTokens.add(refreshToken);
    await renewalBarrier?.future;
    if (renewalError != null) throw renewalError!;
    return AccountBackendSession(
      accessToken: 'new-access-$renewals',
      refreshToken: 'rotated-refresh-$renewals',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      userId: renewedUserId,
      email: 'test@example.invalid',
    );
  }

  @override
  Future<AccountBackendProfile> refreshSession({
    required String accessToken,
    required String deviceId,
    String? friendlyName,
  }) async {
    profiles++;
    lastProfileToken = accessToken;
    await profileBarrier?.future;
    if (profileError != null &&
        (profileErrorCount == null || profiles <= profileErrorCount!)) {
      throw profileError!;
    }
    return AccountBackendProfile(
      accountId: 'user-test',
      email: 'test@example.invalid',
      status: 'active',
      role: AccountBackendRole.pro,
      serverTime: DateTime.now().toUtc(),
    );
  }
}

AccountSessionSnapshot savedSession({
  bool expired = true,
  String? refresh = 'saved-refresh',
  DateTime? lastServerTimestamp,
  DateTime? expiresAt,
}) => AccountSessionSnapshot(
  accessToken: 'saved-access',
  refreshToken: refresh,
  userId: 'user-test',
  email: 'test@example.invalid',
  deviceId: 'test-device',
  role: AccountBackendRole.pro,
  expiresAt:
      expiresAt ??
      DateTime.now().toUtc().add(Duration(days: expired ? -22 : 1)),
  lastServerTimestamp: lastServerTimestamp,
);

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Test condition timed out');
}
