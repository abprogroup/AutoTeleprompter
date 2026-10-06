import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final explicitSelection in [false, true]) {
    test(
      'input telemetry preserves ${explicitSelection ? 'explicit' : 'default'} microphone intent across reloads',
      () async {
        final adapter = SttBrowserAdapter();
        final client = HttpClient();
        final inputReady = Completer<void>();
        adapter.onDiagnostic = (message) {
          if (message == '[Browser STT] Input ready' &&
              !inputReady.isCompleted) {
            inputReady.complete();
          }
        };
        addTearDown(() async {
          client.close(force: true);
          await adapter.stop();
        });
        if (explicitSelection) {
          adapter.setAudioInputDevice('chosen-id', label: 'Chosen USB mic');
        }
        expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
        final uri = Uri.parse(adapter.sttWebViewUrl!);
        final socket = await WebSocket.connect(
          uri.replace(scheme: 'ws', path: '/ws').toString(),
          headers: {'Origin': 'http://localhost:${uri.port}'},
        );
        final subscription = socket.listen((_) {});
        addTearDown(() async {
          await socket.close();
          await subscription.cancel();
        });
        socket.add(
          jsonEncode({'type': 'inputReady', 'label': 'Observed Realtek mic'}),
        );
        await inputReady.future.timeout(const Duration(seconds: 3));

        // Reloading the same authenticated page must carry user intent, not the
        // metering track's observation (which can be a fallback input).
        final response = await (await client.getUrl(uri)).close();
        final page = await response.transform(utf8.decoder).join();
        final expectedId = explicitSelection ? 'chosen-id' : '';
        final expectedLabel =
            explicitSelection ? 'Chosen USB mic' : 'System default microphone';
        expect(page.contains('let selectedDeviceId = "$expectedId";'), isTrue);
        expect(
          page.contains('let selectedDeviceLabel = "$expectedLabel";'),
          isTrue,
        );
        expect(page.contains('Observed Realtek mic'), isFalse);
      },
    );
  }
}
