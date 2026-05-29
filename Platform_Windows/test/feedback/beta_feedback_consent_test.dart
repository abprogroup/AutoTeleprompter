import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/feedback/providers/beta_consent_provider.dart';
import 'package:autoteleprompter/features/feedback/services/feedback_report_service.dart';
import 'package:autoteleprompter/features/feedback/services/lightweight_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fresh beta install creates device key and blocks until consent',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(betaConsentProvider.notifier).ensureLoaded();
    var state = container.read(betaConsentProvider);

    expect(state.loaded, isTrue);
    expect(state.deviceKey, isNotEmpty);
    expect(state.hasAcceptedCurrentPolicy, isFalse);

    await container.read(betaConsentProvider.notifier).acceptCurrentPolicy();
    state = container.read(betaConsentProvider);

    expect(state.hasAcceptedCurrentPolicy, isTrue);
    expect(state.acceptedPolicyVersion, betaPrivacyPolicyVersion);
    expect(state.acceptedAppVersion, betaAppVersion);
    expect(state.acceptedAtIso, isNotEmpty);
  });

  test('withdrawing consent keeps device key and clears acceptance', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(betaConsentProvider.notifier);
    await notifier.ensureLoaded();
    await notifier.acceptCurrentPolicy();
    final accepted = container.read(betaConsentProvider);

    expect(accepted.hasAcceptedCurrentPolicy, isTrue);

    await notifier.withdrawConsent();
    final withdrawn = container.read(betaConsentProvider);

    expect(withdrawn.deviceKey, accepted.deviceKey);
    expect(withdrawn.hasAcceptedCurrentPolicy, isFalse);
    expect(withdrawn.acceptedPolicyVersion, isEmpty);
    expect(withdrawn.acceptedAtIso, isEmpty);
    expect(withdrawn.acceptedAppVersion, isEmpty);
  });

  test('lightweight diagnostics stays capped below payload budget', () {
    final diagnostics = LightweightDiagnostics.instance;
    diagnostics.clear();
    addTearDown(diagnostics.clear);

    for (var i = 0; i < 900; i++) {
      diagnostics.record(
        'stt',
        'event $i ${'x' * 900}',
        data: {'index': i, 'text': 'y' * 900},
      );
    }

    final snapshot = diagnostics.snapshot();
    final encoded = utf8.encode(jsonEncode(snapshot));

    expect(encoded.length, lessThanOrEqualTo(LightweightDiagnostics.maxBytes));
    expect(snapshot['events'], isA<List>());
    expect((snapshot['events'] as List), isNotEmpty);
  });

  test(
      'feedback service queues reports when endpoint is missing and caps outbox',
      () async {
    final temp = await Directory.systemTemp.createTemp('feedback_outbox_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FeedbackReportService(
      endpoint: '',
      outboxDirectory: () async => temp,
    );
    final legacyDir =
        Directory('${temp.path}${Platform.pathSeparator}feedback_outbox');
    await legacyDir.create(recursive: true);
    await File('${legacyDir.path}${Platform.pathSeparator}legacy.json.gz')
        .writeAsBytes(gzip.encode(utf8.encode('{"rawText":"legacy script"}')));

    for (var i = 0; i < 5; i++) {
      final result = await service.submit({
        'reportId': 'rpt_$i',
        'schemaVersion': 1,
        'activeScript': {'rawText': 'script $i'},
      });
      expect(result.sent, isFalse);
      expect(result.queued, isTrue);
    }

    expect(await service.pendingReportCount(), 3);
    expect(
      File('${legacyDir.path}${Platform.pathSeparator}legacy.json.gz')
          .existsSync(),
      isFalse,
    );
    final files = temp
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json.gz.atpe'))
        .toList();
    expect(files, hasLength(3));
    for (final file in files) {
      expect(await file.readAsString(), isNot(contains('script')));
    }

    final retry = await service.retryPendingReports();
    expect(retry.sent, 0);
    expect(retry.remaining, 3);
    expect(retry.lastFailureClass, 'endpointMissing');
    expect(retry.message, contains('Feedback service is not configured'));

    expect(await service.deletePendingReports(), 3);
    expect(await service.pendingReportCount(), 0);
  });

  test('feedback outbox sanitizes report ids used as filenames', () async {
    final temp =
        await Directory.systemTemp.createTemp('feedback_filename_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FeedbackReportService(
      endpoint: '',
      outboxDirectory: () async => temp,
    );
    final result = await service.submit({
      'reportId': r'..\bad/report:id',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'script'},
    });

    expect(result.queued, isTrue);
    final files = temp
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json.gz.atpe'))
        .toList();
    expect(files, hasLength(1));
    expect(files.single.path, isNot(contains('..')));
    expect(files.single.path, isNot(contains('/bad/')));
  });

  test('feedback service rejects non-local http endpoints before sending',
      () async {
    final temp = await Directory.systemTemp.createTemp('feedback_https_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FeedbackReportService(
      endpoint: 'http://example.com/feedback',
      outboxDirectory: () async => temp,
    );
    final result = await service.submit({
      'reportId': 'http-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'script'},
    });

    expect(result.sent, isFalse);
    expect(result.queued, isTrue);
    expect(result.failureClass, 'endpointRejected');
    expect(result.message, contains('HTTPS'));
    expect(await service.pendingReportCount(), 1);
  });

  test('feedback service classifies malformed endpoint transport failures',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('feedback_bad_endpoint_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FeedbackReportService(
      endpoint: 'https://[broken',
      outboxDirectory: () async => temp,
    );
    final result = await service.submit({
      'reportId': 'bad-endpoint-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'script'},
    });

    expect(result.sent, isFalse);
    expect(result.queued, isTrue);
    expect(result.failureClass, 'badEndpointFormat');
    expect(await service.pendingReportCount(), 1);
  });

  test('feedback service times out stalled endpoint sends', () async {
    final temp =
        await Directory.systemTemp.createTemp('feedback_timeout_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final releaseServer = Completer<void>();
    addTearDown(() async {
      releaseServer.complete();
      await server.close(force: true);
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    unawaited(() async {
      await for (final request in server) {
        await request.drain<void>();
        await releaseServer.future;
      }
    }());

    final service = FeedbackReportService(
      endpoint: 'http://127.0.0.1:${server.port}/feedback',
      outboxDirectory: () async => temp,
      requestTimeout: const Duration(milliseconds: 20),
    );
    final result = await service.submit({
      'reportId': 'timeout-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'script'},
    });

    expect(result.sent, isFalse);
    expect(result.queued, isTrue);
    expect(result.failureClass, 'timeout');
    expect(await service.pendingReportCount(), 1);
  });

  test('feedback service follows Apps Script style 302 redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    final requests = <String>[];
    final contentLengths = <int>[];
    unawaited(() async {
      await for (final request in server) {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path == '/start') {
          contentLengths.add(request.contentLength);
          await request.drain<void>();
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, '/done');
          await request.response.close();
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true,"reportId":"redirect-test"}');
          await request.response.close();
        }
      }
    }());

    final service = FeedbackReportService(
      endpoint: 'http://127.0.0.1:${server.port}/start',
    );
    final result = await service.submit({
      'reportId': 'redirect-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'redirect script'},
    });

    expect(result.sent, isTrue);
    expect(result.queued, isFalse);
    expect(requests, ['POST /start', 'GET /done']);
    expect(contentLengths.single, greaterThan(0));
  });

  test('feedback service queues 200 responses without ok true', () async {
    final temp = await Directory.systemTemp.createTemp('feedback_reject_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    unawaited(() async {
      await for (final request in server) {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":false,"error":"bad token"}');
        await request.response.close();
      }
    }());

    final service = FeedbackReportService(
      endpoint: 'http://127.0.0.1:${server.port}/feedback',
      outboxDirectory: () async => temp,
    );
    final result = await service.submit({
      'reportId': 'reject-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'rejected script'},
    });

    expect(result.sent, isFalse);
    expect(result.queued, isTrue);
    expect(result.message, contains('bad token'));
    expect(await service.pendingReportCount(), 1);

    final retry = await service.retryPendingReports();
    expect(retry.sent, 0);
    expect(retry.remaining, 1);
    expect(retry.lastFailureClass, 'serverRejected');
    expect(retry.lastFailureMessage, contains('bad token'));
    expect(retry.message, contains('bad token'));
  });

  test('feedback service trims endpoint whitespace before sending', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    var received = false;
    unawaited(() async {
      await for (final request in server) {
        received = request.uri.path == '/feedback';
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"reportId":"trim-test"}');
        await request.response.close();
      }
    }());

    final service = FeedbackReportService(
      endpoint: ' \r\nhttp://127.0.0.1:${server.port}/feedback\r\n ',
    );
    final result = await service.submit({
      'reportId': 'trim-test',
      'schemaVersion': 1,
      'activeScript': {'rawText': 'trimmed endpoint script'},
    });

    expect(result.sent, isTrue);
    expect(received, isTrue);
  });

  test('feedback service packs large reports as compressed JSON attachment',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));

    String? capturedBody;
    unawaited(() async {
      await for (final request in server) {
        capturedBody = await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"reportId":"large-test"}');
        await request.response.close();
      }
    }());

    const repeatedSecretPhrase = 'sensitive beta rehearsal line ';
    final service = FeedbackReportService(
      endpoint: 'http://127.0.0.1:${server.port}/feedback',
    );
    final result = await service.submit({
      'reportId': 'large-test',
      'schemaVersion': 1,
      'deviceKey': 'device',
      'consentVersion': 'test',
      'appVersion': '5.0.2+17',
      'platform': 'windows',
      'createdAt': DateTime.utc(2026, 5, 24).toIso8601String(),
      'userText': {'title': 'Large', 'description': 'Large report'},
      'activeScript': {
        'title': 'Large Script',
        'sourceType': 'RTF',
        'sessionId': 'session',
        'isRtl': false,
        'rawText': repeatedSecretPhrase * 5000,
        'wordCount': 20000,
      },
      'diagnostics': {
        'ringBuffer': {
          'events': List.generate(
            200,
            (i) => {'type': 'event', 'message': 'diagnostic $i'},
          ),
        },
      },
    });

    expect(result.sent, isTrue);
    final sent = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(sent['activeScript']['rawText'], isNull);
    expect(capturedBody, isNot(contains(repeatedSecretPhrase)));
    expect(sent['transport']['mode'], 'compressedFullReport');

    final compressed = base64Decode(
      sent['transport']['fullReportGzipBase64'] as String,
    );
    final fullReport = utf8.decode(gzip.decode(compressed));
    expect(fullReport, contains(repeatedSecretPhrase));
  });
}
