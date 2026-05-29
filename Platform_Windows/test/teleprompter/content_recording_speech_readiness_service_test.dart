import 'package:autoteleprompter/features/teleprompter/models/alignment_result.dart';
import 'package:autoteleprompter/features/teleprompter/services/content_recording_speech_readiness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording speech readiness accepts listening state', () async {
    final result =
        await const ContentRecordingSpeechReadinessService().waitForReady(
      readState: () => const TeleprompterState(isListening: true),
      timeout: const Duration(milliseconds: 1),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(result.isReady, isTrue);
    expect(result.status, ContentRecordingSpeechReadinessStatus.ready);
  });

  test('recording speech readiness fails on provider error', () async {
    final result =
        await const ContentRecordingSpeechReadinessService().waitForReady(
      readState: () => const TeleprompterState(
        hasError: true,
        statusMessage: 'Microphone unavailable',
      ),
      timeout: const Duration(milliseconds: 1),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(result.isReady, isFalse);
    expect(result.status, ContentRecordingSpeechReadinessStatus.failed);
    expect(result.message, 'Microphone unavailable');
  });

  test('recording speech readiness times out while still starting', () async {
    final result =
        await const ContentRecordingSpeechReadinessService().waitForReady(
      readState: () => const TeleprompterState(isStarting: true),
      timeout: const Duration(milliseconds: 2),
      pollInterval: const Duration(milliseconds: 1),
    );

    expect(result.isReady, isFalse);
    expect(result.status, ContentRecordingSpeechReadinessStatus.timedOut);
  });
}
