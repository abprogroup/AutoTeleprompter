import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:autoteleprompter/features/settings/services/cloud_oauth_service.dart';
import 'package:autoteleprompter/features/settings/services/cloud_sign_in_runtime.dart';
import 'package:autoteleprompter/features/settings/services/cloud_connection_store.dart';
import 'cloud_connection_refresh_test.dart' show MemoryCloudStore;

final dropbox = CloudConnectionStore.providers.firstWhere(
  (p) => p.id == 'dropbox',
);
final google = CloudConnectionStore.providers.firstWhere(
  (p) => p.id == 'google_drive',
);

class SignInHarness {
  final store = MemoryCloudStore();
  final client = HttpClient();
  late HttpServer api;
  late CloudOAuthService service;
  final uris = <Uri>[];
  final ports = <int>[];
  final requests = <String>[];
  int released = 0;
  int tokenStatus = 200;
  int accountStatus = 200;
  int? bindError;
  bool browserFails = false;
  bool leaseBusy = false;
  Completer<void>? tokenGate;
  Completer<void>? accountGate;
  Duration timeout = const Duration(seconds: 2);
  Map<String, Object?> tokens = {
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'expires_in': 3600,
  };

  Future<void> init() async {
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((request) async {
      final token = request.uri.path.endsWith('/token');
      requests.add(token ? 'token' : 'account');
      try {
        await request.drain<void>();
      } catch (_) {
        return;
      }
      await (token ? tokenGate?.future : accountGate?.future);
      request.response.statusCode = token ? tokenStatus : accountStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(token ? tokens : {'email': 'new@example.test'}),
      );
      try {
        await request.response.close();
      } catch (_) {}
    });
    service = CloudOAuthService(
      encryptedStore: store,
      httpClient: OnlyLoopbackClient(client, api.port),
      now: () => DateTime.utc(2026, 10, 28),
      requestTimeout: timeout,
      credentials: const CloudOAuthCredentials(
        googleClientId: '12345-test.apps.googleusercontent.com',
        dropboxClientId: 'test-dropbox-id',
      ),
      signInRuntime: CloudSignInRuntime(
        callbackTimeout: timeout,
        acquireLease:
            () async =>
                leaseBusy
                    ? null
                    : CloudSignInLease(() async {
                      released++;
                    }),
        bindServer: (port) async {
          ports.add(port);
          if (bindError != null) {
            throw SocketException(
              'test bind',
              osError: OSError('test', bindError!),
            );
          }
          return HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        },
        openBrowser: (uri) async {
          uris.add(uri);
          if (browserFails) throw const ProcessException('test', []);
        },
      ),
    );
  }

  void seed() => store.seed('dropbox', expiry: DateTime.utc(2026, 10, 29));
  Future<int> callback({
    String? state,
    String? error,
    String path = '/oauth/callback',
  }) async {
    final auth = uris.last;
    final redirect = Uri.parse(auth.queryParameters['redirect_uri']!);
    final uri = redirect.replace(
      host: '127.0.0.1',
      path: path,
      queryParameters: {
        'state': state ?? auth.queryParameters['state']!,
        if (error == null)
          'code': 'fake-authorization-code'
        else
          'error': error,
      },
    );
    final response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
    return response.statusCode;
  }

  Future<void> portIsFree() async {
    final port = Uri.parse(uris.last.queryParameters['redirect_uri']!).port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    await server.close(force: true);
  }

  Future<void> dispose() async {
    service.cancelSignIn();
    for (final gate in [tokenGate, accountGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await until(() => service.activeSignIn.value == null);
    client.close(force: true);
    await api.close(force: true);
  }
}

class OnlyLoopbackClient implements HttpClient {
  OnlyLoopbackClient(this.inner, this.port);
  final HttpClient inner;
  final int port;
  Uri local(Uri uri) {
    if (!{
      'api.dropboxapi.com',
      'oauth2.googleapis.com',
      'www.googleapis.com',
    }.contains(uri.host)) {
      throw StateError('Unexpected test host');
    }
    return uri.replace(scheme: 'http', host: '127.0.0.1', port: port);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri uri) => inner.postUrl(local(uri));
  @override
  Future<HttpClientRequest> getUrl(Uri uri) => inner.getUrl(local(uri));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Test wait expired');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
