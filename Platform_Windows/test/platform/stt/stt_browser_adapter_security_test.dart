import 'dart:io';

import 'package:autoteleprompter/platform/stt/stt_browser_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SttBrowserAdapter adapter;
  late HttpClient client;

  setUp(() {
    adapter = SttBrowserAdapter();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await adapter.stop();
  });

  test('serves only the current authenticated loopback session', () async {
    final result = await adapter.start(localeId: 'he-IL');
    expect(result.success, isTrue);

    final sessionUri = Uri.parse(adapter.sttWebViewUrl!);
    final token = sessionUri.queryParameters['session'];
    expect(sessionUri.host, 'localhost');
    expect(sessionUri.port, inInclusiveRange(8082, 8092));
    expect(token, isNotNull);
    expect(token, hasLength(32));

    final authenticated = await _get(client, sessionUri);
    expect(authenticated.statusCode, HttpStatus.ok);
    expect(authenticated.body, contains('const sessionToken ='));
    expect(authenticated.body, contains("type: 'heartbeat'"));
    expect(
      authenticated.body,
      contains('analyser.getFloatTimeDomainData(timeDataArray)'),
    );
    expect(authenticated.body, contains('20 * Math.log10'));
    expect(authenticated.body, contains('const meterSilenceFloorDb = -60'));
    expect(authenticated.body, contains('const meterAttack = 0.45'));
    expect(authenticated.body, contains('const meterRelease = 0.10'));
    expect(authenticated.body, contains('now - lastMeterSendAt >= 100'));
    expect(
      authenticated.body,
      contains('meterTimer = setInterval(sampleMeter, 100);'),
    );
    expect(authenticated.body, isNot(contains('requestAnimationFrame')));
    expect(authenticated.body, contains('function resetMeter()'));
    final visualizerStartup = _sourceSection(
      authenticated.body,
      'async function initVisualizer()',
      'function startMeterSampling()',
    );
    expect(visualizerStartup, contains('refreshDevices();'));
    expect(visualizerStartup, isNot(contains('await refreshDevices();')));
    expect(authenticated.body, contains('now - startRequestedAt > 10000'));
    expect(authenticated.body, contains('recognizer.onresult = (e) =>'));
    expect(
      authenticated.body,
      contains('if(!isCurrentRecognition(recognizer, generation)) return;'),
    );
    expect(authenticated.body, contains('recognizer.start(track)'));
    expect(authenticated.body, contains('recognizer.start()'));
    expect(authenticated.body, contains('startRecognitionWithConfiguredInput'));
    expect(
      authenticated.body,
      contains("recognitionInputMode = 'selected-stream'"),
    );
    expect(
      authenticated.body,
      contains("recognitionInputMode = 'default-microphone'"),
    );
    expect(authenticated.body, contains('recognizer.maxAlternatives = 3'));
    expect(authenticated.body, contains('const snapshotParts = [];'));
    expect(
      authenticated.body,
      contains('for(let i = 0; i < e.results.length; i++)'),
    );
    expect(authenticated.body, contains("snapshotParts.join(' ').trim()"));
    expect(authenticated.body, contains("words: snapshotTranscript"));
    expect(authenticated.body, contains('isCumulative: true'));
    expect(authenticated.body, contains('streamId: generation'));
    expect(authenticated.body, contains('alternatives: alternatives'));
    expect(
      authenticated.body,
      contains("if(selectedDeviceId && track && track.readyState === 'live')"),
    );
    expect(authenticated.body, isNot(contains('speechEvidence')));
    expect(authenticated.body, isNot(contains('audioEvidence')));
    expect(authenticated.body, isNot(contains('restartRecognizer')));
    expect(authenticated.body, isNot(contains('stale-speech-events')));
    expect(authenticated.body, isNot(contains('watchdog-stale')));
    expect(
      authenticated.body,
      isNot(contains('switchingLocale = false; consecutiveFails = 0;')),
    );

    final missingToken = await _get(
      client,
      sessionUri.replace(queryParameters: const {}),
    );
    expect(missingToken.statusCode, HttpStatus.forbidden);

    final wrongToken = await _get(
      client,
      sessionUri.replace(queryParameters: const {'session': 'wrong'}),
    );
    expect(wrongToken.statusCode, HttpStatus.forbidden);
  });

  test('rotates the browser session token after restart', () async {
    expect((await adapter.start(localeId: 'en-US')).success, isTrue);
    final first = Uri.parse(adapter.sttWebViewUrl!);

    expect((await adapter.start(localeId: 'en-US')).success, isTrue);
    final second = Uri.parse(adapter.sttWebViewUrl!);

    expect(
      second.queryParameters['session'],
      isNot(first.queryParameters['session']),
    );

    final stale = await _get(client, first);
    expect(stale.statusCode, HttpStatus.forbidden);

    final current = await _get(client, second);
    expect(current.statusCode, HttpStatus.ok);
  });

  test('remaps a configured microphone inside each browser profile', () async {
    adapter.setAudioInputDevice(
      'webview-profile-device-id',
      label: 'Microphone Array (Realtek Audio)',
    );
    expect((await adapter.start(localeId: 'he-IL')).success, isTrue);

    final page = await _get(client, Uri.parse(adapter.sttWebViewUrl!));

    expect(page.statusCode, HttpStatus.ok);
    expect(
      page.body,
      contains('let selectedDeviceLabel = "Microphone Array (Realtek Audio)";'),
    );
    expect(page.body, contains('function findConfiguredAudioInput(inputs)'));
    expect(page.body, contains('d.id === selectedDeviceId'));
    expect(page.body, contains('normalizeAudioInputLabel(d.label) === wanted'));
    expect(page.body, contains('partialMatches.length === 1'));
    expect(page.body, contains('audioConstraints(remapped.id)'));
    expect(page.body, contains("selectedDeviceLabel = d.label ||"));
  });
}

Future<({int statusCode, String body})> _get(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  final body = await response.transform(const SystemEncoding().decoder).join();
  return (statusCode: response.statusCode, body: body);
}

String _sourceSection(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: 'Missing source marker: $startMarker');
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, greaterThan(start), reason: 'Missing source marker: $endMarker');
  return source.substring(start, end);
}
