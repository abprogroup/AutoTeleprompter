import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SttBrowserLifecycleEvent', () {
    test('parses the bounded page lifecycle protocol', () {
      const expected = <String, SttBrowserLifecyclePhase>{
        'socketConnected': SttBrowserLifecyclePhase.socketConnected,
        'microphoneReady': SttBrowserLifecyclePhase.microphoneReady,
        'recognizerListening': SttBrowserLifecyclePhase.recognizerListening,
        'speechApiUnavailable': SttBrowserLifecyclePhase.speechApiUnavailable,
        'permissionDenied': SttBrowserLifecyclePhase.permissionDenied,
        'network': SttBrowserLifecyclePhase.network,
      };

      for (final entry in expected.entries) {
        final event = SttBrowserLifecycleEvent.fromBrowserMessage({
          'type': 'lifecycle',
          'phase': entry.key,
          'transcript': 'must be ignored',
          'deviceId': 'must be ignored',
        });
        expect(event?.phase, entry.value, reason: entry.key);
      }

      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'lifecycle',
          'phase': 'disconnected',
        }),
        isNull,
        reason: 'disconnect is owned by the server socket lifecycle',
      );
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'lifecycle',
          'phase': 'private-payload',
        }),
        isNull,
      );
    });

    test('maps legacy readiness and failure messages', () {
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'inputReady',
        })?.phase,
        SttBrowserLifecyclePhase.microphoneReady,
      );
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'listening',
        })?.phase,
        SttBrowserLifecyclePhase.recognizerListening,
      );
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'error',
          'error': 'speech-api-unavailable',
        })?.phase,
        SttBrowserLifecyclePhase.speechApiUnavailable,
      );
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'error',
          'error': 'service-not-allowed',
        })?.phase,
        SttBrowserLifecyclePhase.permissionDenied,
      );
      expect(
        SttBrowserLifecycleEvent.fromBrowserMessage(const {
          'type': 'error',
          'error': 'network',
        })?.phase,
        SttBrowserLifecyclePhase.network,
      );
    });

    test('creates canonical runtime-health events without payload data', () {
      const event = SttBrowserLifecycleEvent(
        SttBrowserLifecyclePhase.permissionDenied,
      );
      final health = event.toRuntimeHealth(locale: 'he-IL', hasListened: true);

      expect(health.type, 'permissionDenied');
      expect(health.error, 'not-allowed');
      expect(health.failures, 1);
      expect(health.listening, isFalse);
      expect(health.locale, 'he-IL');
    });

    test('sanitizes arbitrary browser error payloads', () {
      expect(sanitizeSttBrowserErrorCode('network'), 'network');
      expect(sanitizeSttBrowserErrorCode('not-allowed'), 'not-allowed');
      expect(sanitizeSttBrowserErrorCode('private transcript'), 'unknown');
      expect(sanitizeSttBrowserErrorCode({'deviceId': 'secret'}), 'unknown');
    });
  });

  group('SttBrowserAdapter lifecycle integration', () {
    late SttBrowserAdapter adapter;
    late List<SttRuntimeHealth> healthEvents;
    late List<String> diagnostics;
    late List<String> errors;
    late List<SpeechResult> results;
    late List<double> soundLevels;

    setUp(() {
      adapter = SttBrowserAdapter();
      healthEvents = <SttRuntimeHealth>[];
      diagnostics = <String>[];
      errors = <String>[];
      results = <SpeechResult>[];
      soundLevels = <double>[];
      adapter.onRuntimeHealth = healthEvents.add;
      adapter.onDiagnostic = diagnostics.add;
      adapter.onError = errors.add;
      adapter.onResult = results.add;
      adapter.onSoundLevelChange = soundLevels.add;
    });

    tearDown(() async {
      await adapter.stop();
    });

    test(
      'served page announces every explicit browser lifecycle phase',
      () async {
        expect((await adapter.start(localeId: 'en-US')).success, isTrue);
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        final request = await client.getUrl(Uri.parse(adapter.sttWebViewUrl!));
        final response = await request.close();
        final html = await response.transform(utf8.decoder).join();

        expect(response.statusCode, HttpStatus.ok);
        expect(html, contains("sendLifecycle('socketConnected')"));
        expect(html, contains("sendLifecycle('microphoneReady')"));
        expect(html, contains("sendLifecycle('recognizerListening')"));
        expect(html, contains("sendLifecycle('speechApiUnavailable')"));
        expect(html, contains("sendLifecycle('permissionDenied')"));
        expect(html, contains("sendLifecycle('network')"));
      },
    );

    test('emits ordered readiness and bounded failure phases', () async {
      expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
      final sessionUri = Uri.parse(adapter.sttWebViewUrl!);
      final socket = await _connect(sessionUri);
      final subscription = socket.listen((_) {});

      socket.add(
        jsonEncode(const {'type': 'lifecycle', 'phase': 'socketConnected'}),
      );
      socket.add(
        jsonEncode(const {'type': 'lifecycle', 'phase': 'microphoneReady'}),
      );
      socket.add(
        jsonEncode(const {
          'type': 'inputReady',
          'label': 'Private microphone label',
        }),
      );
      socket.add(
        jsonEncode(const {'type': 'lifecycle', 'phase': 'recognizerListening'}),
      );
      socket.add(jsonEncode(const {'type': 'lifecycle', 'phase': 'network'}));
      socket.add(jsonEncode(const {'type': 'lifecycle', 'phase': 'network'}));
      socket.add(
        jsonEncode(const {'type': 'lifecycle', 'phase': 'permissionDenied'}),
      );

      await _waitUntil(
        () =>
            healthEvents
                .where((event) => event.type == 'permissionDenied')
                .length ==
            1,
      );

      expect(healthEvents.map((event) => event.type), <String>[
        'socketConnected',
        'microphoneReady',
        'recognizerListening',
        'network',
        'network',
        'permissionDenied',
      ]);
      expect(
        healthEvents.where((event) => event.error == 'network'),
        hasLength(2),
      );
      expect(errors, hasLength(1));
      expect(errors.single, isNot(contains('Private microphone label')));

      await socket.close();
      await _waitUntil(
        () => healthEvents.any((event) => event.type == 'disconnected'),
      );
      final disconnected = healthEvents.last;
      expect(disconnected.type, 'disconnected');
      expect(disconnected.error, 'browser-disconnected');
      expect(disconnected.failures, 1);

      await subscription.cancel();
    });

    test(
      'accepts current-session results without speechstart or VAD',
      () async {
        expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
        final socket = await _connect(Uri.parse(adapter.sttWebViewUrl!));
        final subscription = socket.listen((_) {});

        socket.add(
          jsonEncode(const {
            'type': 'result',
            'words': 'spoken without speechstart',
            'isFinal': false,
          }),
        );
        socket.add(
          jsonEncode(const {
            'type': 'result',
            'words': 'final without speechstart',
            'isFinal': true,
          }),
        );
        await _waitUntil(() => results.length == 2);
        expect(results.map((result) => result.words), <String>[
          'spoken without speechstart',
          'final without speechstart',
        ]);

        socket.add(
          jsonEncode(const {'type': 'result', 'words': '   ', 'isFinal': true}),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(results, hasLength(2));

        await socket.close();
        await subscription.cancel();
      },
    );

    test('preserves cumulative browser snapshots and alternatives', () async {
      expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
      final socket = await _connect(Uri.parse(adapter.sttWebViewUrl!));
      final subscription = socket.listen((_) {});

      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'נפגשים הוקמה בשנת 20',
          'isFinal': false,
          'isCumulative': true,
          'streamId': 7,
          'alternatives': [
            'נפגשים הוקמה בשנת עשרים',
            'נפגשים הוקמה בשנת 20',
            '',
            22,
          ],
        }),
      );

      await _waitUntil(() => results.length == 1);
      final result = results.single;
      expect(result.words, 'נפגשים הוקמה בשנת 20');
      expect(result.isFinal, isFalse);
      expect(result.isCumulative, isTrue);
      expect(result.streamId, 7);
      expect(result.alternatives, <String>['נפגשים הוקמה בשנת עשרים']);

      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'legacy without stream id',
          'isFinal': true,
          'isCumulative': true,
        }),
      );
      await _waitUntil(() => results.length == 2);
      expect(results.last.isCumulative, isFalse);

      await socket.close();
      await subscription.cancel();
    });

    test('meter telemetry alone never fabricates a transcript', () async {
      expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
      final socket = await _connect(Uri.parse(adapter.sttWebViewUrl!));
      final subscription = socket.listen((_) {});

      for (final level in <double>[0.0, 0.02, 0.20, 0.08, 0.30, 0.0]) {
        socket.add(jsonEncode({'type': 'level', 'level': level}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results, isEmpty);
      expect(
        healthEvents.where((event) => event.type == 'recognizerUnproductive'),
        isEmpty,
      );

      await socket.close();
      await subscription.cancel();
    });

    test(
      'waits for authenticated close acknowledgement before shutdown',
      () async {
        expect((await adapter.start(localeId: 'en-US')).success, isTrue);
        final socket = await _connect(Uri.parse(adapter.sttWebViewUrl!));
        final subscription = socket.listen((message) async {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'close') {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            socket.add(jsonEncode(const {'type': 'closeAck'}));
          }
        });

        socket.add(jsonEncode(const {'type': 'level', 'level': 0.75}));
        await _waitUntil(
          () => soundLevels.isNotEmpty && soundLevels.last == 0.75,
        );

        var completed = false;
        final stopFuture = adapter.stop().whenComplete(() => completed = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);

        await stopFuture.timeout(const Duration(seconds: 1));
        expect(completed, isTrue);
        expect(soundLevels.last, 0.0);

        await subscription.cancel();
      },
    );

    test(
      'rejects stale sockets and does not expose sensitive values in logs',
      () async {
        const deviceId = 'private-device-id-123';
        const transcript = 'private transcript text';
        adapter.setAudioInputDevice(
          deviceId,
          label: 'Private microphone label',
        );
        expect((await adapter.start(localeId: 'en-US')).success, isTrue);
        final firstUri = Uri.parse(adapter.sttWebViewUrl!);
        final firstToken = firstUri.queryParameters['session']!;

        final firstSocket = await _connect(firstUri);
        final firstSubscription = firstSocket.listen((_) {});
        firstSocket.add(
          jsonEncode(const {'type': 'lifecycle', 'phase': 'socketConnected'}),
        );
        await _waitUntil(
          () => healthEvents.any((event) => event.type == 'socketConnected'),
        );

        expect((await adapter.start(localeId: 'en-US')).success, isTrue);
        healthEvents.clear();
        final secondUri = Uri.parse(adapter.sttWebViewUrl!);
        expect(secondUri.queryParameters['session'], isNot(firstToken));

        await expectLater(
          _connect(firstUri),
          throwsA(isA<WebSocketException>()),
        );

        final secondSocket = await _connect(secondUri);
        final secondSubscription = secondSocket.listen((_) {});
        secondSocket.add(
          jsonEncode(const {'type': 'lifecycle', 'phase': 'socketConnected'}),
        );
        secondSocket.add(
          jsonEncode(const {
            'type': 'result',
            'words': transcript,
            'isFinal': true,
          }),
        );
        secondSocket.add(
          jsonEncode({
            'type': 'error',
            'error': '$transcript $deviceId $firstToken',
          }),
        );

        await _waitUntil(
          () =>
              healthEvents.any((event) => event.type == 'error') &&
              healthEvents.any((event) => event.type == 'socketConnected'),
        );
        expect(
          healthEvents.where((event) => event.type == 'socketConnected'),
          hasLength(1),
        );
        expect(
          healthEvents.singleWhere((event) => event.type == 'error').error,
          'unknown',
        );

        final diagnosticText = diagnostics.join('\n');
        expect(diagnosticText, isNot(contains(firstToken)));
        expect(diagnosticText, isNot(contains(transcript)));
        expect(diagnosticText, isNot(contains(deviceId)));
        expect(diagnosticText, isNot(contains('Private microphone label')));

        await secondSocket.close();
        await firstSubscription.cancel();
        await secondSubscription.cancel();
      },
    );
  });
}

Future<WebSocket> _connect(Uri sessionUri) {
  final socketUri = sessionUri.replace(scheme: 'ws', path: '/ws');
  return WebSocket.connect(
    socketUri.toString(),
    headers: {'Origin': 'http://localhost:${sessionUri.port}'},
  );
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not reached', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
