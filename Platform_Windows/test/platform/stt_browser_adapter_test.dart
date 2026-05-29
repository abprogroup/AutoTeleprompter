import 'dart:io';

import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser STT falls back when the default port is busy', () async {
    HttpServer? blocker;
    try {
      blocker = await HttpServer.bind('localhost', 8082);
    } on SocketException {
      return;
    }
    addTearDown(() => blocker?.close(force: true));

    final adapter = SttBrowserAdapter();
    addTearDown(adapter.stop);

    final result = await adapter.start(localeId: 'en_US');
    expect(result.success, isTrue);

    final pageUrl = Uri.parse(adapter.sttWebViewUrl!);
    expect(pageUrl.port, inInclusiveRange(8083, 8092));
  });

  test('browser STT rejects stale websocket sessions', () async {
    final adapter = SttBrowserAdapter();
    addTearDown(adapter.stop);

    final result = await adapter.start(localeId: 'en_US');
    expect(result.success, isTrue);

    final pageUrl = Uri.parse(adapter.sttWebViewUrl!);
    final staleUrl = pageUrl.replace(
      scheme: 'ws',
      path: '/ws',
      queryParameters: {'session': '999999'},
    );

    await expectLater(
      WebSocket.connect(staleUrl.toString()),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('browser STT page and stale responses use hardened headers', () async {
    final adapter = SttBrowserAdapter();
    addTearDown(adapter.stop);

    final result = await adapter.start(localeId: 'en_US');
    expect(result.success, isTrue);

    final client = HttpClient();
    addTearDown(client.close);
    final pageUrl = Uri.parse(adapter.sttWebViewUrl!);

    final pageRequest = await client.getUrl(pageUrl);
    final pageResponse = await pageRequest.close();
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(pageResponse.headers.value(HttpHeaders.cacheControlHeader),
        'no-store');
    expect(pageResponse.headers.value('x-content-type-options'), 'nosniff');
    expect(pageResponse.headers.contentType?.mimeType, 'text/html');
    await pageResponse.drain<void>();

    final staleRequest = await client.getUrl(
      pageUrl.replace(path: '/ws', queryParameters: {'session': '999999'}),
    );
    final staleResponse = await staleRequest.close();
    expect(staleResponse.statusCode, HttpStatus.forbidden);
    expect(staleResponse.headers.value(HttpHeaders.cacheControlHeader),
        'no-store');
    expect(staleResponse.headers.value('x-content-type-options'), 'nosniff');
    await staleResponse.drain<void>();
  });

  test('browser STT accepts the active websocket session', () async {
    final adapter = SttBrowserAdapter();
    addTearDown(adapter.stop);

    final result = await adapter.start(localeId: 'en_US');
    expect(result.success, isTrue);

    final pageUrl = Uri.parse(adapter.sttWebViewUrl!);
    final activeUrl = pageUrl.replace(scheme: 'ws', path: '/ws');
    final socket = await WebSocket.connect(activeUrl.toString());
    addTearDown(socket.close);

    expect(socket.readyState, WebSocket.open);
  });
}
