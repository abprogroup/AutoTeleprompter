import 'package:autoteleprompter/features/teleprompter/services/stt_transcript_buffer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SttTranscriptBufferService', () {
    const service = SttTranscriptBufferService();

    test('keeps only the recent transcript tail', () {
      final buffer = service.update(
        rawTranscript: 'one two three four five six',
        transcriptFloor: 0,
        recentWordWindow: 3,
      );

      expect(buffer.recentTranscript, 'four five six');
      expect(buffer.freshWords, ['one', 'two', 'three', 'four', 'five', 'six']);
    });

    test('uses transcriptFloor after true off-script reset', () {
      final buffer = service.update(
        rawTranscript: 'old words before reset new words',
        transcriptFloor: 4,
        recentWordWindow: 12,
      );

      expect(buffer.freshWords, ['new', 'words']);
      expect(buffer.recentTranscript, 'new words');
    });

    test('resets floor when Apple starts a shorter transcript source', () {
      final buffer = service.update(
        rawTranscript: 'fresh source',
        transcriptFloor: 12,
        recentWordWindow: 12,
      );

      expect(buffer.resetFloor, isTrue);
      expect(buffer.transcriptFloor, 0);
      expect(buffer.freshWords, ['fresh', 'source']);
    });
  });
}
