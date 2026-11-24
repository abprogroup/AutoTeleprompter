import 'package:autoteleprompter/features/teleprompter/services/stt_transcript_buffer_service.dart';
import 'package:autoteleprompter/platform/stt/sherpa_transcript_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SherpaTranscriptEmitter', () {
    test('suppresses punctuation-only updates and endpoint replays so repeated blessings never double-jump', () {
      final emitter = SherpaTranscriptEmitter();

      // First Hebrew blessing recognized.
      final first = emitter.prepareEmission(
        'ברוך אתה אדוני אלוהינו מלך העולם',
        forceFinal: false,
      )!;
      expect(first.isFinal, isFalse);

      // Model adds trailing period on the exact same words -> MUST NOT re-emit!
      expect(
        emitter.prepareEmission(
          'ברוך אתה אדוני אלוהינו מלך העולם.',
          forceFinal: false,
        ),
        isNull,
      );

      // Endpoint fires with the exact same words -> MUST NOT replay!
      expect(
        emitter.prepareEmission(
          'ברוך אתה אדוני אלוהינו מלך העולם.',
          forceFinal: true,
        ),
        isNull,
      );
    });

    test('sets isFinal=true when an earlier word is revised so SttTranscriptBufferService never black-holes new speech', () {
      final emitter = SherpaTranscriptEmitter();
      const bufferService = SttTranscriptBufferService();

      final first = emitter.prepareEmission(
        'declaration of fai',
        forceFinal: false,
      )!;
      expect(first.isFinal, isFalse);

      final revised = emitter.prepareEmission(
        'declaration of faith our risen messiah',
        forceFinal: false,
      )!;
      expect(revised.isFinal, isTrue);

      final updated = bufferService.update(
        rawTranscript: revised.text,
        transcriptFloor: 3,
        cumulativeReplacement: true,
        cumulativeBaselineWords: const ['declaration', 'of', 'fai'],
        cumulativeFinal: revised.isFinal,
      );
      expect(updated.hasFreshSpeech, isTrue);
      expect(updated.freshWords, ['faith', 'our', 'risen', 'messiah']);

      final extended = emitter.prepareEmission(
        'declaration of faith our risen messiah is king',
        forceFinal: false,
      )!;
      expect(extended.isFinal, isFalse);
    });
  });
}
