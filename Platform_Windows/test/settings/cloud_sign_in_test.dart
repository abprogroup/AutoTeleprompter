import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoteleprompter/features/settings/services/cloud_sign_in_runtime.dart';
import 'package:autoteleprompter/features/settings/services/cloud_oauth_service.dart';
import 'cloud_sign_in_test_support.dart';

void main() {
  late SignInHarness h;
  setUp(() async {
    h = SignInHarness();
    await h.init();
  });
  tearDown(() => h.dispose());

  test(
    'double-click and other provider share one sign-in, cancel frees port',
    () async {
      h.seed();
      final first = h.service.connect(dropbox);
      final second = await h.service.connect(dropbox);
      final other = await h.service.connect(google);
      expect(second.connected, false);
      expect(other.connected, false);
      await until(() => h.uris.isNotEmpty);
      expect(h.ports, [51747]);
      expect(h.uris, hasLength(1));
      h.service.cancelSignIn();
      expect((await first).message, contains('cancelled'));
      await h.portIsFree();
      expect(h.released, 1);
      expect(
        h.store.payload('dropbox')['token']['access_token'],
        'saved-access',
      );
      final retry = h.service.connect(dropbox);
      await until(() => h.uris.length == 2);
      await h.callback();
      expect((await retry).connected, true);
    },
  );

  test(
    'foreign and stale callbacks do not consume the active request',
    () async {
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      expect(await h.callback(state: 'old-attempt'), 400);
      expect(await h.callback(path: '/favicon.ico'), 400);
      expect(h.requests, isEmpty);
      await h.callback();
      expect((await pending).connected, true);
    },
  );

  test(
    'callback port released before slow token exchange; cancellation cannot write later',
    () async {
      h.seed();
      h.tokenGate = Completer<void>();
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      await h.callback();
      await until(() => h.requests.contains('token'));
      await h.portIsFree();
      h.service.cancelSignIn();
      expect((await pending).connected, false);
      h.tokenGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.store.writes, 0);
      expect(h.released, 1);
    },
  );

  test(
    'callback port released during account verification and old connection preserved on failure',
    () async {
      h.seed();
      h.accountGate = Completer<void>();
      h.accountStatus = 503;
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      await h.callback();
      await until(() => h.requests.contains('account'));
      await h.portIsFree();
      h.accountGate!.complete();
      expect((await pending).connected, false);
      expect(h.store.writes, 0);
      expect(
        (await h.service.authorizeAccount('dropbox'))!.accessToken,
        'saved-access',
      );
    },
  );

  test('callback timeout closes listener and lease', () async {
    final pending = h.service.connect(dropbox);
    await until(() => h.uris.isNotEmpty);
    expect((await pending).message, contains('timed out'));
    await h.portIsFree();
    expect(h.released, 1);
    expect(h.service.activeSignIn.value, isNull);
  });

  test(
    'browser failure closes listener, keeps saved token and allows retry',
    () async {
      h.seed();
      h.browserFails = true;
      expect((await h.service.connect(dropbox)).connected, false);
      await h.portIsFree();
      expect(h.store.writes, 0);
      h.browserFails = false;
      final retry = h.service.connect(dropbox);
      await until(() => h.uris.length == 2);
      await h.callback();
      expect((await retry).connected, true);
    },
  );

  test('another instance blocks before opening browser or binding', () async {
    h.leaseBusy = true;
    expect(
      (await h.service.connect(dropbox)).message,
      contains('Another AutoTeleprompter'),
    );
    expect(h.ports, isEmpty);
    expect(h.uris, isEmpty);
    expect(h.service.activeSignIn.value, isNull);
  });

  for (final code in [10048, 10013]) {
    test(
      'bind failure $code classified without changing Dropbox registered port',
      () async {
        h.seed();
        h.bindError = code;
        final result = await h.service.connect(dropbox);
        expect(result.connected, false);
        expect(h.ports, [51747]);
        expect(result.message.contains('in use'), code == 10048);
        expect(h.uris, isEmpty);
        expect(h.store.writes, 0);
        expect(h.released, 1);
      },
    );
  }

  test(
    'successful PKCE connection validated before replacing encrypted account',
    () async {
      h.seed();
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      expect(h.uris.single.queryParameters['code_challenge_method'], 'S256');
      expect(h.store.writes, 0);
      await h.callback();
      final result = await pending;
      expect(result.connected, true);
      expect(result.account!.accountLabel, 'new@example.test');
      expect(h.store.writes, 1);
      expect(
        h.store.payload('dropbox')['token']['refresh_token'],
        'new-refresh',
      );
      await h.portIsFree();
    },
  );

  test(
    'denied consent does not echo provider error or discard account',
    () async {
      h.seed();
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      await h.callback(error: 'secret-untrusted-error');
      final result = await pending;
      expect(result.message, isNot(contains('secret-untrusted-error')));
      expect(h.requests, isEmpty);
      expect(h.store.writes, 0);
      await h.portIsFree();
    },
  );

  test(
    'disconnect during account lookup wins over late successful callback',
    () async {
      h.seed();
      h.accountGate = Completer<void>();
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      await h.callback();
      await until(() => h.requests.contains('account'));
      await h.service.disconnect('dropbox');
      h.accountGate!.complete();
      expect((await pending).connected, false);
      expect(await h.service.loadAccount('dropbox'), isNull);
    },
  );

  test(
    'check connection verifies existing account without browser or callback listener',
    () async {
      h.seed();
      final result = await h.service.checkConnection(dropbox);
      expect(result.connected, true);
      expect(h.requests, ['account']);
      expect(h.uris, isEmpty);
      expect(h.ports, isEmpty);
      expect(h.store.writes, 0);
    },
  );

  test('failed connection check never deletes existing credentials', () async {
    h.seed();
    h.accountStatus = 401;
    expect((await h.service.checkConnection(dropbox)).connected, false);
    expect(await h.service.loadAccount('dropbox'), isNotNull);
    expect(h.store.writes, 0);
    expect(h.uris, isEmpty);
  });

  for (final accountStatus in [200, 503]) {
    test(
      'disconnect invalidates a pending connection check ($accountStatus)',
      () async {
        h.seed();
        h.accountStatus = accountStatus;
        h.accountGate = Completer<void>();
        final pending = h.service.checkConnection(dropbox);
        await until(() => h.requests.contains('account'));
        await h.service.disconnect('dropbox');
        h.accountGate!.complete();
        final result = await pending;
        expect(result.connected, isFalse);
        expect(result.account, isNull);
        expect(result.message, contains('Connection changed'));
        expect(result.message, isNot(contains('internet')));
        expect(result.message, isNot(contains('verified')));
        expect(await h.service.loadAccount('dropbox'), isNull);
        expect(
          h.service.connectionStates.value['dropbox'],
          CloudConnectionStatus.disconnected,
        );
        expect(h.store.writes, 0);
        expect(h.uris, isEmpty);
      },
    );
  }

  test(
    'cancelled reconnect does not invalidate an existing in-flight renewal',
    () async {
      h.store.seed('dropbox');
      h.tokenGate = Completer<void>();
      final renewal = h.service.authorizeAccount('dropbox');
      await until(() => h.requests.contains('token'));
      final reconnect = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      h.service.cancelSignIn();
      expect((await reconnect).connected, false);
      h.tokenGate!.complete();
      expect((await renewal)!.accessToken, 'new-access');
      expect(h.store.writes, 1);
    },
  );

  test(
    'account lookup timeout preserves saved account and does not hold port',
    () async {
      h.seed();
      h.accountGate = Completer<void>();
      final pending = h.service.connect(dropbox);
      await until(() => h.uris.isNotEmpty);
      await h.callback();
      await until(() => h.requests.contains('account'));
      await h.portIsFree();
      expect((await pending).message, contains('timed out'));
      expect(h.store.writes, 0);
      expect(h.released, 1);
    },
  );

  test('Google retains its existing allowed callback range', () async {
    h.bindError = 10048;
    final result = await h.service.connect(google);
    expect(result.connected, false);
    expect(h.ports, List.generate(21, (i) => 51747 + i));
    expect(h.uris, isEmpty);
  });

  test(
    'callback duplicates complete once without unhandled completer errors',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final session = CloudOAuthCallbackSession(server, 'current');
      final client = HttpClient();
      try {
        Future<int> request() async {
          final uri = Uri.parse(
            'http://127.0.0.1:${server.port}/oauth/callback?state=current&code=test',
          );
          final response = await (await client.getUrl(uri)).close();
          await response.drain<void>();
          return response.statusCode;
        }

        final statuses = await Future.wait([request(), request()]);
        expect(statuses.where((s) => s == 200), hasLength(1));
        expect(statuses.where((s) => s == 400), hasLength(1));
        expect((await session.result).code, 'test');
      } finally {
        await session.close();
        client.close(force: true);
      }
    },
  );

  test(
    'Windows lease prevents second holder and can be reacquired after release',
    () async {
      // Tests use a new isolated temporary directory, never user credentials.
      final dir = await Directory.systemTemp.createTemp('atp-oauth-lock-test-');
      final file = File('${dir.path}/oauth-sign-in.lock');
      final first = await CloudSignInLease.acquire(file);
      expect(first, isNotNull);
      try {
        expect(await CloudSignInLease.acquire(file), isNull);
      } finally {
        await first!.release();
      }
      final second = await CloudSignInLease.acquire(file);
      expect(second, isNotNull);
      await second!.release();
      // Kept for diagnostics: no deletion of user or test files in this milestone.
    },
    skip: !Platform.isWindows,
  );
}
