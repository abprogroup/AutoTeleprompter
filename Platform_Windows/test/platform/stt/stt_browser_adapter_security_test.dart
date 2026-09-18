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
      contains('Date.now() - window.lastVolSend > 100'),
    );
    expect(authenticated.body, contains('evidenceNow > speechEvidenceUntil'));
    expect(
      authenticated.body,
      contains('startRecognitionWithSelectedInput(recognizer)'),
    );
    expect(authenticated.body, contains('recognizer.start(track)'));
    expect(authenticated.body, contains('recognizer.start()'));
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
