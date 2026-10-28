import 'dart:async';

import 'account_backend_models.dart';
import 'account_backend_service.dart';
import 'account_session_store.dart';

/// Owns renewal and encrypted persistence. Never changes account permissions.
class AccountSessionManager {
  AccountSessionManager({
    required AccountBackendService backend,
    required AccountSessionStore store,
    DateTime Function()? now,
  }) : _backend = backend,
       _store = store,
       _now = now ?? DateTime.now;

  final AccountBackendService _backend;
  final AccountSessionStore _store;
  final DateTime Function() _now;
  Future<AccountSessionSnapshot>? _renewal;
  Future<void> _writes = Future<void>.value();
  int _generation = 0;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<AccountSessionSnapshot?> read() => _serialize(_store.read);

  Future<void> save(
    AccountSessionSnapshot session, {
    String? expectedAccessToken,
  }) {
    final generation = _generation;
    return _serialize(() async {
      _checkGeneration(generation);
      if (expectedAccessToken != null &&
          (await _store.read())?.accessToken != expectedAccessToken) {
        throw const AccountBackendError('session_changed', 'Account changed.');
      }
      await _store.save(session);
    });
  }

  Future<void> clear() {
    _generation++;
    _renewal = null;
    return _serialize(_store.clear);
  }

  void invalidatePending() {
    _generation++;
    _renewal = null;
  }

  Future<AccountSessionSnapshot> validSession({bool forceRefresh = false}) {
    final pending = _renewal;
    if (pending != null) return pending;
    final generation = _generation;
    final operation = _readAndRenew(generation, forceRefresh);
    _renewal = operation;
    // Both branches consume completion; no unhandled whenComplete future.
    operation.then<void>(
      (_) {
        if (identical(_renewal, operation)) _renewal = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_renewal, operation)) _renewal = null;
      },
    );
    return operation;
  }

  Future<AccountSessionSnapshot> _readAndRenew(
    int generation,
    bool forceRefresh,
  ) async {
    final saved = await read();
    _checkGeneration(generation);
    if (saved == null || saved.accessToken.isEmpty) {
      throw const AccountBackendError('signed_out', 'Sign in to your account.');
    }
    final now = _now().toUtc();
    if (saved.lastServerTimestamp != null &&
        now.isBefore(
          saved.lastServerTimestamp!.subtract(const Duration(minutes: 5)),
        )) {
      throw const AccountBackendError(
        'clock_rollback',
        'Check the date and time on this computer.',
      );
    }
    final expiry = saved.expiresAt;
    if (!forceRefresh &&
        expiry != null &&
        expiry.isAfter(now.add(const Duration(minutes: 2)))) {
      return saved;
    }
    final refresh = saved.refreshToken?.trim() ?? '';
    if (refresh.isEmpty) {
      if (!forceRefresh && expiry != null && expiry.isAfter(now)) return saved;
      throw const AccountBackendError(
        'refresh_token_missing',
        'Sign in again to renew this connection.',
      );
    }
    final renewed = await _backend.refreshAccessToken(refreshToken: refresh);
    _checkGeneration(generation);
    if (renewed.accessToken.isEmpty ||
        renewed.refreshToken == null ||
        renewed.refreshToken!.isEmpty ||
        renewed.expiresAt == null ||
        !renewed.expiresAt!.isAfter(now)) {
      throw const AccountBackendError(
        'invalid_refresh_response',
        'Account renewal returned an incomplete response.',
      );
    }
    if (saved.userId != null &&
        renewed.userId != null &&
        saved.userId != renewed.userId) {
      throw const AccountBackendError(
        'session_identity_changed',
        'Sign in again to verify this account.',
      );
    }
    final result = AccountSessionSnapshot(
      accessToken: renewed.accessToken,
      refreshToken: renewed.refreshToken,
      userId: renewed.userId ?? saved.userId,
      email: renewed.email ?? saved.email,
      deviceId: saved.deviceId,
      role: saved.role,
      expiresAt: renewed.expiresAt,
      lastServerTimestamp: saved.lastServerTimestamp,
      graceToken: saved.graceToken,
      graceExpiresAt: saved.graceExpiresAt,
    );
    // Persist rotated credentials before profile/network work can fail.
    await save(result, expectedAccessToken: saved.accessToken);
    _checkGeneration(generation);
    return result;
  }

  void _checkGeneration(int generation) {
    if (generation != _generation) {
      throw const AccountBackendError('session_changed', 'Account changed.');
    }
  }

  static bool requiresSignIn(Object error) =>
      error is AccountBackendError &&
      const {
        'refresh_token_missing',
        'refresh_token_not_found',
        'refresh_token_already_used',
        'invalid_grant',
        'session_not_found',
        'session_expired',
        'user_banned',
        'user_not_found',
        'session_identity_changed',
      }.contains(error.code);
}
