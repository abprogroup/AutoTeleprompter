import '../models/alignment_result.dart';

/// Ported as available capability - not yet wired into
/// `content_creator_screen.dart`. Android's Content Creator screen doesn't
/// drive its own scroll from the real STT/teleprompter session yet (it uses
/// a separate manual scroll controller); wiring recording start to wait on
/// genuine STT readiness only makes sense once that deeper integration
/// exists. See `android_parity_gaps.md` #15.
enum ContentRecordingSpeechReadinessStatus {
  ready,
  failed,
  timedOut,
}

class ContentRecordingSpeechReadinessResult {
  final ContentRecordingSpeechReadinessStatus status;
  final TeleprompterState state;
  final String message;

  const ContentRecordingSpeechReadinessResult({
    required this.status,
    required this.state,
    required this.message,
  });

  bool get isReady => status == ContentRecordingSpeechReadinessStatus.ready;
}

class ContentRecordingSpeechReadinessService {
  const ContentRecordingSpeechReadinessService();

  Future<ContentRecordingSpeechReadinessResult> waitForReady({
    required TeleprompterState Function() readState,
    Duration timeout = const Duration(seconds: 4),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final state = readState();
      final statusMessage = state.statusMessage.trim();
      if (state.isListening && !state.hasError) {
        return ContentRecordingSpeechReadinessResult(
          status: ContentRecordingSpeechReadinessStatus.ready,
          state: state,
          message: 'speech-to-text listening',
        );
      }
      if (state.hasError) {
        return ContentRecordingSpeechReadinessResult(
          status: ContentRecordingSpeechReadinessStatus.failed,
          state: state,
          message: statusMessage.isEmpty
              ? 'speech-to-text reported an error'
              : statusMessage,
        );
      }
      if (!state.isStarting && !state.isListening && statusMessage.isNotEmpty) {
        return ContentRecordingSpeechReadinessResult(
          status: ContentRecordingSpeechReadinessStatus.failed,
          state: state,
          message: statusMessage,
        );
      }
      if (!DateTime.now().isBefore(deadline)) {
        return ContentRecordingSpeechReadinessResult(
          status: ContentRecordingSpeechReadinessStatus.timedOut,
          state: state,
          message: 'speech-to-text did not become ready in time',
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
