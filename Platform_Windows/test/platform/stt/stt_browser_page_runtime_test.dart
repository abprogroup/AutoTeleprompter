import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';

import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('authenticated adapter delivers browser phrase provenance', () async {
    final adapter = SttBrowserAdapter();
    addTearDown(adapter.stop);
    final result = Completer<SpeechResult>();
    adapter.onResult = result.complete;
    expect((await adapter.start(localeId: 'en-US')).success, isTrue);
    final uri = Uri.parse(adapter.sttWebViewUrl!);
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '/ws').toString(),
      headers: {'Origin': uri.origin},
    );
    addTearDown(socket.close);
    socket.add(
      jsonEncode({
        'type': 'result',
        'words': 'settled phrase fresh words',
        'isFinal': false,
        'isCumulative': true,
        'streamId': 3,
        'segments': ['settled phrase', 'fresh words'],
        'finalizedSegmentCount': 1,
      }),
    );
    final speech = await result.future.timeout(const Duration(seconds: 3));
    expect(speech.browserSegments, ['settled phrase', 'fresh words']);
    expect(speech.browserFinalizedSegmentCount, 1);
    expect(speech.streamId, 3);
  });
  test(
    'execute served browser page with deterministic recognition lifecycle',
    () async {
      final adapter = SttBrowserAdapter();
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await adapter.stop();
      });
      expect((await adapter.start(localeId: 'en-US')).success, isTrue);
      final request = await client.getUrl(Uri.parse(adapter.sttWebViewUrl!));
      final response = await request.close();
      final html = await utf8.decoder.bind(response).join();
      final process = await Process.start('node', [
        'test/platform/stt/browser_page_runtime.cjs',
      ]);
      final output = utf8.decoder.bind(process.stdout).join();
      final errors = utf8.decoder.bind(process.stderr).join();
      process.stdin.write(html);
      await process.stdin.close();
      expect(
        await process.exitCode,
        0,
        reason: '${await output}\n${await errors}',
      );
      expect(await output, contains('browser lifecycle checks passed'));
    },
  );
}
