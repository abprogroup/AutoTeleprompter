import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoteleprompter/core/security/encrypted_file_store.dart';
import 'package:autoteleprompter/features/settings/services/cloud_oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  late MemoryCloudStore store;
  late CloudOAuthService oauth;
  late DateTime now;
  late int status;
  late Map<String, Object?> response;
  late List<Map<String, String>> requests;
  Completer<void>? barrier;

  setUp(() async {
    now = DateTime.utc(2026, 10, 28);
    status = 200;
    response = {'access_token': 'renewed-access', 'expires_in': 3600};
    requests = [];
    barrier = null;
    store = MemoryCloudStore();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient();
    server.listen((request) async {
      requests.add(
        Uri.splitQueryString(await utf8.decoder.bind(request).join()),
      );
      await barrier?.future;
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    oauth = CloudOAuthService(
      encryptedStore: store,
      httpClient: _LoopbackOnlyClient(client, server.port),
      now: () => now,
      credentials: const CloudOAuthCredentials(
        googleClientId: '12345-test.apps.googleusercontent.com',
        dropboxClientId: 'test-dropbox-id',
      ),
      requestTimeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    if (barrier != null && !barrier!.isCompleted) barrier!.complete();
    for (final gate in [store.readGate, store.writeGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    client.close(force: true);
    await server.close(force: true);
  });

  for (final provider in ['google_drive', 'dropbox']) {
    test('$provider renews the saved October 6 expiry without login', () async {
      store.seed(provider);
      final result = await oauth.authorizeAccount(provider);
      expect(result!.accessToken, 'renewed-access');
      expect(requests.single['grant_type'], 'refresh_token');
      expect(requests.single['refresh_token'], 'saved-refresh');
      expect(
        store.payload(provider)['token']['refresh_token'],
        'saved-refresh',
      );
      expect(
        store.payload(provider)['account']['expiresAtIso'],
        '2026-10-28T01:00:00.000Z',
      );
      expect(
        oauth.connectionStates.value[provider],
        CloudConnectionStatus.available,
      );
      await oauth.authorizeAccount(provider);
      expect(requests, hasLength(1));
    });
  }

  test('concurrent startup and sync requests renew only once', () async {
    store.seed('google_drive');
    barrier = Completer<void>();
    final futures = List.generate(
      7,
      (_) => oauth.authorizeAccount('google_drive'),
    );
    await _until(() => requests.isNotEmpty);
    barrier!.complete();
    await Future.wait(futures);
    expect(requests, hasLength(1));
    expect(store.writes, 1);
  });

  test('fresh token needs no HTTP request', () async {
    store.seed('dropbox', expiry: now.add(const Duration(hours: 1)));
    expect(
      (await oauth.authorizeAccount('dropbox'))!.accessToken,
      'saved-access',
    );
    expect(requests, isEmpty);
  });

  test('two minute safety margin renews before actual expiry', () async {
    store.seed('dropbox', expiry: now.add(const Duration(minutes: 1)));
    await oauth.authorizeAccount('dropbox');
    expect(requests, hasLength(1));
  });

  test('new refresh token replaces old one when provider rotates it', () async {
    store.seed('dropbox');
    response['refresh_token'] = 'rotated-refresh';
    await oauth.authorizeAccount('dropbox');
    expect(
      store.payload('dropbox')['token']['refresh_token'],
      'rotated-refresh',
    );
  });

  test(
    '5xx preserves saved credentials and backs off before automatic retry',
    () async {
      store.seed('google_drive');
      status = 503;
      response = {
        'error': 'temporarily_unavailable',
        'detail': 'SECRET_RESPONSE_DO_NOT_LOG',
      };
      await expectLater(
        oauth.authorizeAccount('google_drive'),
        throwsA(
          predicate(
            (e) =>
                e is CloudConnectionException &&
                !e.toString().contains('SECRET_RESPONSE'),
          ),
        ),
      );
      await oauth.maintainConnections();
      expect(requests, hasLength(1));
      expect(
        store.payload('google_drive')['token']['refresh_token'],
        'saved-refresh',
      );
      now = now.add(const Duration(seconds: 31));
      status = 200;
      response = {'access_token': 'recovered', 'expires_in': 3600};
      await oauth.maintainConnections();
      expect(requests, hasLength(2));
      expect(
        oauth.connectionStates.value['google_drive'],
        CloudConnectionStatus.available,
      );
    },
  );

  test(
    'invalid grant asks for reconnect and does not repeatedly hit provider',
    () async {
      store.seed('dropbox');
      status = 400;
      response = {'error': 'invalid_grant'};
      await oauth.maintainConnections();
      now = now.add(const Duration(days: 1));
      await oauth.maintainConnections();
      expect(requests, hasLength(1));
      expect(
        oauth.connectionStates.value['dropbox'],
        CloudConnectionStatus.signInRequired,
      );
      expect(store.writes, 0);
    },
  );

  test('disconnect wins against late renewal completion', () async {
    store.seed('dropbox');
    barrier = Completer<void>();
    final pending = oauth.authorizeAccount('dropbox');
    await _until(() => requests.isNotEmpty);
    await oauth.disconnect('dropbox');
    barrier!.complete();
    expect(await pending, isNull);
    expect(store.data, isEmpty);
    expect(
      oauth.connectionStates.value['dropbox'],
      CloudConnectionStatus.disconnected,
    );
  });

  test('account listing waits for the entire renewal write', () async {
    store.seed('dropbox');
    store.writeGate = Completer<void>();
    final renewal = oauth.authorizeAccount('dropbox');
    await _until(() => store.writing);
    Object? readError;
    CloudAccountInfo? account;
    var readFinished = false;
    final listing = oauth
        .loadAccount('dropbox')
        .then<void>(
          (value) {
            account = value;
            readFinished = true;
          },
          onError: (Object error) {
            readError = error;
            readFinished = true;
          },
        );
    // Drain scheduled microtasks while the synthetic truncated write is held.
    await Future<void>.delayed(Duration.zero);
    final finishedDuringWrite = readFinished;
    store.writeGate!.complete();
    await Future.wait([renewal, listing]);
    expect(
      readError,
      isNull,
      reason: 'Never decode a partially written envelope',
    );
    expect(finishedDuringWrite, isFalse);
    expect(account!.expiresAtIso, '2026-10-28T01:00:00.000Z');
    expect(store.writes, 1);
  });

  test('later disconnect waits for a complete account read', () async {
    store.seed('dropbox', expiry: now.add(const Duration(hours: 1)));
    store.readGate = Completer<void>();
    Object? readError;
    CloudAccountInfo? account;
    final listing = oauth
        .loadAccount('dropbox')
        .then<void>(
          (value) {
            account = value;
          },
          onError: (Object error) {
            readError = error;
          },
        );
    await _until(() => store.reads == 1);
    final disconnect = oauth.disconnect('dropbox');
    await Future<void>.delayed(Duration.zero);
    final deletedDuringRead = store.data.isEmpty;
    store.readGate!.complete();
    await Future.wait([listing, disconnect]);
    expect(
      readError,
      isNull,
      reason: 'A queued deletion cannot interrupt a read',
    );
    expect(deletedDuringRead, isFalse);
    expect(account, isNull, reason: 'Do not return the disconnected account');
    expect(await oauth.loadAccount('dropbox'), isNull);
    expect(
      oauth.connectionStates.value['dropbox'],
      CloudConnectionStatus.disconnected,
    );
  });

  test(
    'storage failure does not poison subsequent account operations',
    () async {
      store.data['dropbox'] = Uint8List.fromList(utf8.encode('{'));
      await expectLater(oauth.loadAccount('dropbox'), throwsFormatException);
      store.seed('dropbox', expiry: now.add(const Duration(hours: 1)));
      expect(await oauth.loadAccount('dropbox'), isNotNull);
      await oauth.disconnect('dropbox');
      expect(await oauth.loadAccount('dropbox'), isNull);
    },
  );

  test('blocked provider storage does not block another provider', () async {
    store.seed('google_drive', expiry: now.add(const Duration(hours: 1)));
    store.seed('dropbox');
    store.writeGate = Completer<void>();
    final renewal = oauth.authorizeAccount('dropbox');
    await _until(() => store.writing);
    try {
      final account = await oauth
          .loadAccount('google_drive')
          .timeout(const Duration(seconds: 1));
      expect(account!.providerId, 'google_drive');
      expect(store.writing, isTrue);
    } finally {
      store.writeGate!.complete();
      await renewal;
    }
  });

  test('provider timeout is bounded and never removes saved account', () async {
    store.seed('google_drive');
    barrier = Completer<void>();
    await expectLater(
      oauth.authorizeAccount('google_drive'),
      throwsA(isA<CloudConnectionException>()),
    );
    expect(store.data, isNotEmpty);
    expect(store.writes, 0);
    expect(
      oauth.connectionStates.value['google_drive'],
      CloudConnectionStatus.retrying,
    );
  });

  test(
    'malformed success must not reuse an old access token as renewed',
    () async {
      store.seed('dropbox');
      response = {'expires_in': 3600};
      await expectLater(
        oauth.authorizeAccount('dropbox'),
        throwsA(isA<CloudConnectionException>()),
      );
      expect(store.writes, 0);
      expect(
        oauth.connectionStates.value['dropbox'],
        isNot(CloudConnectionStatus.available),
      );
    },
  );

  test('missing refresh token does not attempt invalid renewal', () async {
    store.seed('dropbox', refresh: null);
    await oauth.maintainConnections();
    expect(requests, isEmpty);
    expect(
      oauth.connectionStates.value['dropbox'],
      CloudConnectionStatus.signInRequired,
    );
  });

  test('unconnected accounts do not trigger login or requests', () async {
    await oauth.maintainConnections();
    expect(requests, isEmpty);
    expect(store.writes, 0);
  });
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  throw StateError('Test condition timed out');
}

class _LoopbackOnlyClient implements HttpClient {
  final HttpClient delegate;
  final int port;
  _LoopbackOnlyClient(this.delegate, this.port);
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    if (!{'oauth2.googleapis.com', 'api.dropboxapi.com'}.contains(url.host)) {
      throw StateError('Unexpected provider');
    }
    return delegate.postUrl(Uri.parse('http://127.0.0.1:$port/token'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory fixture: never reads the user's actual account files.
class MemoryCloudStore extends EncryptedFileStore {
  final data = <String, Uint8List>{};
  int writes = 0;
  int reads = 0;
  bool writing = false;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  void seed(
    String provider, {
    DateTime? expiry,
    String? refresh = 'saved-refresh',
  }) {
    data[provider] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'account': {
            'providerId': provider,
            'providerLabel': provider,
            'accountLabel': 'test@example.invalid',
            'connectedAtIso': '2026-09-30T12:00:00Z',
            'expiresAtIso':
                (expiry ?? DateTime.utc(2026, 10, 6)).toIso8601String(),
          },
          'token': {
            'access_token': 'saved-access',
            'refresh_token': refresh,
            'expires_in': 3600,
          },
        }),
      ),
    );
  }

  dynamic payload(String provider) => jsonDecode(utf8.decode(data[provider]!));
  @override
  Future<File?> fileFor({
    required String collection,
    required String id,
    required String extension,
  }) async => data.containsKey(id) ? File(id) : null;
  @override
  Future<Uint8List> readBytes(File file, {required String kind}) async {
    reads++;
    await readGate?.future;
    return data[file.path]!;
  }

  @override
  Future<File> writeBytes({
    required String collection,
    required String id,
    required String extension,
    required List<int> bytes,
    required String kind,
    bool compress = true,
  }) async {
    writing = true;
    try {
      if (writeGate != null) {
        // The real store writes in place. This gate models an incomplete
        // envelope deterministically without touching the user's filesystem.
        data[id] = Uint8List.fromList(utf8.encode('{'));
        await writeGate!.future;
      }
      data[id] = Uint8List.fromList(bytes);
      writes++;
      return File(id);
    } finally {
      writing = false;
    }
  }

  @override
  Future<void> delete({
    required String collection,
    required String id,
    required String extension,
  }) async {
    data.remove(id);
  }
}
