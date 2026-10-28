import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Owns only this app's temporary sign-in resources. Never terminates a process
/// or deletes a lock file (deleting it would allow two different lock owners).
class CloudSignInLease {
  CloudSignInLease(this._release);
  final Future<void> Function() _release;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }

  static Future<CloudSignInLease?> acquire(File file) async {
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      // Nonblocking, handle-owned Windows lock. The OS releases it on crash.
      await handle.lock(FileLock.exclusive, 0, 1);
    } on FileSystemException catch (error) {
      await handle.close();
      // ERROR_LOCK_VIOLATION. Other errors must not be mislabeled as busy.
      if (error.osError?.errorCode == 33) return null;
      rethrow;
    }
    return CloudSignInLease(() async {
      try {
        await handle.unlock(0, 1);
      } finally {
        await handle.close();
      }
    });
  }
}

class CloudSignInRuntime {
  const CloudSignInRuntime({
    this.bindServer = _bind,
    this.openBrowser = _openBrowser,
    this.acquireLease = _acquireLease,
    this.callbackTimeout = const Duration(minutes: 3),
  });
  final Future<HttpServer> Function(int port) bindServer;
  final Future<void> Function(Uri uri) openBrowser;
  final Future<CloudSignInLease?> Function() acquireLease;
  final Duration callbackTimeout;

  static Future<HttpServer> _bind(int port) =>
      HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: false);

  static Future<CloudSignInLease?> _acquireLease() async {
    final directory = await getApplicationSupportDirectory();
    return CloudSignInLease.acquire(
      File('${directory.path}${Platform.pathSeparator}oauth-sign-in.lock'),
    );
  }

  static Future<void> _openBrowser(Uri uri) async {
    final result =
        Platform.isWindows
            ? await Process.run('rundll32', [
              'url.dll,FileProtocolHandler',
              '$uri',
            ])
            : await Process.run('open', ['$uri']);
    if (result.exitCode != 0) throw const ProcessException('browser', []);
  }
}

class CloudOAuthCallback {
  const CloudOAuthCallback({this.code, this.error});
  final String? code;
  final String? error;
}

class CloudOAuthCallbackSession {
  CloudOAuthCallbackSession(this.server, this.expectedState) {
    _subscription = server.listen(
      _handle,
      onError: (Object _) {
        _finish(const CloudOAuthCallback(error: 'listener_failed'));
      },
      onDone: () => _finish(const CloudOAuthCallback(error: 'listener_closed')),
    );
  }
  final HttpServer server;
  final String expectedState;
  final _result = Completer<CloudOAuthCallback>();
  late final StreamSubscription<HttpRequest> _subscription;
  bool _claimed = false;
  Future<void>? _closing;
  Future<CloudOAuthCallback> get result => _result.future;

  void _finish(CloudOAuthCallback result) {
    if (!_result.isCompleted) _result.complete(result);
  }

  Future<void> _handle(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final valid =
        request.method == 'GET' &&
        request.uri.path == '/oauth/callback' &&
        query['state'] == expectedState;
    final accepts = valid && !_claimed;
    if (accepts) _claimed = true; // Claim before any await: duplicate-safe.
    try {
      request.response.statusCode =
          accepts ? HttpStatus.ok : HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(
        accepts
            ? '<html><body>Sign-in received. Return to AutoTeleprompter to finish.</body></html>'
            : '<html><body>This is not the active sign-in request.</body></html>',
      );
      await request.response.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Closing a browser tab cannot strand a valid callback.
    } finally {
      if (accepts) {
        _finish(CloudOAuthCallback(code: query['code'], error: query['error']));
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _finish(const CloudOAuthCallback(error: 'listener_closed'));
    await server.close(force: true);
    await _subscription.cancel();
  }
}
