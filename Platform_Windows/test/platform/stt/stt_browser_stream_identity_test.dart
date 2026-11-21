import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SttBrowserAdapter adapter;
  late List<SpeechResult> results;
  late List<String> diagnostics;

  setUp(() {
    adapter = SttBrowserAdapter();
    results = [];
    diagnostics = [];
    adapter.onResult = results.add;
    adapter.onDiagnostic = diagnostics.add;
  });
  tearDown(() async => adapter.stop());

  Future<WebSocket> connect() async {
    final uri = Uri.parse(adapter.sttWebViewUrl!);
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '/ws').toString(),
      headers: {'Origin': uri.origin},
    );
    final subscription = socket.listen((message) {
      if ((jsonDecode(message as String) as Map)['type'] == 'close') {
        socket.add(jsonEncode({'type': 'closeAck'}));
      }
    });
    addTearDown(() async {
      await socket.close();
      await subscription.cancel();
    });
    return socket;
  }

  test('page replacement cannot reuse a consumed transcript stream', () async {
    final healthTypes = <String>[];
    adapter.onRuntimeHealth = (event) => healthTypes.add(event.type);
    expect((await adapter.start()).success, isTrue);
    final first = await connect();
    _result(first, 1, 'old consumed transcript');
    await _waitFor(() => results.length == 1);
    final oldId = results.last.streamId;
    _result(first, 1, 'old consumed transcript corrected');
    await _waitFor(() => results.length == 2);
    expect(
      results.last.streamId,
      oldId,
      reason: 'same stream revisions stay related',
    );

    final replacement = await connect();
    _result(replacement, 1, 'fresh speech after page reload');
    await _waitFor(() => results.length == 3);
    expect(
      results.last.streamId,
      isNot(oldId),
      reason: 'the page restarts its raw generation at one after reload',
    );
    final replacementId = results.last.streamId;
    _result(replacement, 1, 'fresh speech after page reload grows');
    await _waitFor(() => results.length == 4);
    expect(results.last.streamId, replacementId);
    expect(results.every((r) => r.isCumulative), isTrue);
    expect(
      healthTypes,
      isNot(contains('disconnected')),
      reason:
          'the replaced socket closing must not disconnect the current page',
    );
  });

  test(
    'adapter stop/start cannot reuse a consumed transcript stream',
    () async {
      expect((await adapter.start()).success, isTrue);
      final first = await connect();
      _result(first, 1, 'old consumed transcript');
      await _waitFor(() => results.length == 1);
      final oldId = results.last.streamId;
      expect((await adapter.start()).success, isTrue);
      final replacement = await connect();
      _result(replacement, 1, 'fresh speech after host recovery');
      await _waitFor(() => results.length == 2);
      expect(results.last.streamId, isNot(oldId));
    },
  );

  test(
    'late retired generation cannot reopen speech on a current socket',
    () async {
      expect((await adapter.start()).success, isTrue);
      final socket = await connect();
      _result(socket, 1, 'first generation');
      _result(socket, 3, 'replacement generation');
      _result(socket, 1, 'late retired speech');
      _result(socket, 3, 'replacement generation grows');
      await _waitFor(() => results.any((r) => r.words.endsWith('grows')));
      expect(results.map((r) => r.words), [
        'first generation',
        'replacement generation',
        'replacement generation grows',
      ]);
      expect(results[1].streamId, isNot(results[0].streamId));
      expect(results[2].streamId, results[1].streamId);
    },
  );

  test(
    'restart diagnostics are bounded metadata, not browser payload text',
    () async {
      expect((await adapter.start()).success, isTrue);
      final socket = await connect();
      socket.add(
        jsonEncode({
          'type': 'restartScheduled',
          'reason': 'recognition-ended',
          'delayMs': 500,
          'generation': 8,
          'emptyEnds': 3,
          'words': 'private transcript',
          'deviceId': 'private device',
        }),
      );
      socket.add(
        jsonEncode({
          'type': 'restartScheduled',
          'reason': 'private transcript',
          'delayMs': -100,
          'generation': 'private device',
          'emptyEnds': 999999,
        }),
      );
      _result(socket, 1, 'delivery fence');
      await _waitFor(() => results.length == 1);
      final rows =
          diagnostics.where((s) => s.contains('Restart scheduled')).toList();
      expect(rows, hasLength(2));
      expect(rows.first, contains('reason=recognition-ended delayMs=500'));
      expect(rows.first, contains('generation=8 emptyEnds=3'));
      expect(
        rows.last,
        contains('reason=unknown delayMs=0 generation=0 emptyEnds=32'),
      );
      expect(rows.join('\n'), isNot(contains('private')));
      expect(results.single.words, 'delivery fence');
    },
  );

  test(
    'malformed cumulative identity cannot bypass the transcript boundary',
    () async {
      expect((await adapter.start()).success, isTrue);
      final socket = await connect();
      final health = <String>[];
      adapter.onRuntimeHealth = (event) => health.add(event.type);
      for (final generation in [null, 0, -1, 1.5, '1']) {
        socket.add(
          jsonEncode({
            'type': 'result',
            'words': 'untrusted cumulative text',
            'isCumulative': true,
            'streamId': generation,
          }),
        );
      }
      socket.add(
        jsonEncode({'type': 'result', 'words': 'genuine legacy result'}),
      );
      await _waitFor(
        () => results.any((r) => r.words == 'genuine legacy result'),
      );
      expect(results.map((r) => r.words), ['genuine legacy result']);
      expect(results.single.isCumulative, isFalse);
      expect(health.where((type) => type == 'productiveResult'), hasLength(1));
    },
  );
}

void _result(WebSocket socket, int generation, String text) {
  socket.add(
    jsonEncode({
      'type': 'result',
      'words': text,
      'isFinal': false,
      'isCumulative': true,
      'streamId': generation,
    }),
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Result not delivered');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
