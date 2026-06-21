import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_service.dart';
import 'package:autoteleprompter/features/feedback/services/feedback_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeedbackReportService', () {
    test('uses account backend first when configured', () async {
      final backend = _FakeAccountBackendService();
      final service = FeedbackReportService(
        accountBackendConfig: _configuredBackend,
        accountBackendService: backend,
      );

      final result = await service.submit(_report('backend_1'));

      expect(result.sent, isTrue);
      expect(result.queued, isFalse);
      expect(result.reportId, 'backend_1');
      expect(backend.payloads, hasLength(1));
      expect(jsonDecode(backend.payloads.single)['reportId'], 'backend_1');
    });

    test('accepts localhost feedback endpoint for development', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, Object?>>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add(Map<String, Object?>.from(jsonDecode(body) as Map));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true}));
        await request.response.close();
      });

      try {
        final service = FeedbackReportService(
          endpoint: 'http://127.0.0.1:${server.port}',
          accountBackendConfig: const AccountBackendConfig(enabled: false),
        );

        final result = await service.submit(_report('local_1'));

        expect(result.sent, isTrue);
        expect(result.queued, isFalse);
        expect(result.reportId, 'local_1');
        expect(received.single['reportId'], 'local_1');
      } finally {
        await server.close(force: true);
      }
    });
  });
}

const _configuredBackend = AccountBackendConfig(
  enabled: true,
  supabaseUrl: 'https://example.supabase.co',
  anonKey: 'anon-key',
);

Map<String, Object?> _report(String id) => {
      'schemaVersion': 1,
      'reportId': id,
      'deviceKey': 'device',
      'consentVersion': 'test',
      'appVersion': '5.0.0+8',
      'platform': 'ios',
      'createdAt': '2026-06-21T00:00:00Z',
      'userText': {
        'category': 'Bug',
        'severity': 'Normal',
        'title': 'Title',
        'description': 'Description',
      },
      'diagnostics': const {},
    };

class _FakeAccountBackendService extends AccountBackendService {
  _FakeAccountBackendService() : super(config: _configuredBackend);

  final List<String> payloads = [];

  @override
  Future<void> submitFeedbackPayload(String payload) async {
    payloads.add(payload);
  }
}
