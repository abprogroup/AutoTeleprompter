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

    expect(await service.deletePendingReports(), 3);
    expect(await service.pendingReportCount(), 0);
  });
}
