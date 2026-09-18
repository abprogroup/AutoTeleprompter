import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:autoteleprompter/platform/stt/abstract_stt_service.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:autoteleprompter/platform/stt/stt_browser_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SttSpeechEvidenceGate', () {
    late Duration now;
    late SttSpeechEvidenceGate gate;

    setUp(() {
      now = Duration.zero;
      gate = SttSpeechEvidenceGate(
        now: () => now,
        trailingGrace: const Duration(seconds: 4),
      );
    });

    test('accepts only active speech and its bounded final-result grace', () {
      expect(gate.acceptsResult, isFalse);

      gate.speechEnded();
      expect(gate.acceptsResult, isFalse);

      gate.speechStarted();
      expect(gate.acceptsResult, isTrue);

      gate.speechEnded();
      now = const Duration(seconds: 4);
      expect(gate.acceptsResult, isTrue);

      now = const Duration(seconds: 4, milliseconds: 1);
      expect(gate.acceptsResult, isFalse);
    });

    test('reset clears active and trailing evidence', () {
      gate.speechStarted();
      gate.speechEnded();
      expect(gate.acceptsResult, isTrue);

      gate.reset();

      expect(gate.acceptsResult, isFalse);
    });
  });

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

    setUp(() {
      adapter = SttBrowserAdapter();
      healthEvents = <SttRuntimeHealth>[];
      diagnostics = <String>[];
      errors = <String>[];
      results = <SpeechResult>[];
      adapter.onRuntimeHealth = healthEvents.add;
      adapter.onDiagnostic = diagnostics.add;
      adapter.onError = errors.add;
      adapter.onResult = results.add;
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

    test('rejects results without authenticated speech evidence', () async {
      expect((await adapter.start(localeId: 'he-IL')).success, isTrue);
      final socket = await _connect(Uri.parse(adapter.sttWebViewUrl!));
      final subscription = socket.listen((_) {});

      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'ambient',
          'isFinal': false,
        }),
      );
      socket.add(jsonEncode(const {'type': 'speechEnd'}));
      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'still ambient',
          'isFinal': false,
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results, isEmpty);

      socket.add(jsonEncode(const {'type': 'speechStart'}));
      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'spoken',
          'isFinal': false,
        }),
      );
      socket.add(jsonEncode(const {'type': 'speechEnd'}));
      socket.add(
        jsonEncode(const {
          'type': 'result',
          'words': 'final spoken',
          'isFinal': true,
        }),
      );
      await _waitUntil(() => results.length == 2);
      expect(results.map((result) => result.words), <String>[
        'spoken',
        'final spoken',
      ]);

      socket.add(jsonEncode(const {'type': 'speechReset'}));
      socket.add(
        jsonEncode(const {'type': 'result', 'words': 'stale', 'isFinal': true}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(results, hasLength(2));

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

        var completed = false;
        final stopFuture = adapter.stop().whenComplete(() => completed = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(completed, isFalse);

        await stopFuture.timeout(const Duration(seconds: 1));
        expect(completed, isTrue);

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
