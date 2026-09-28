import 'package:autoteleprompter/features/teleprompter/services/stt_transcript_buffer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = SttTranscriptBufferService();

  test('browser phrase shards reset a floor that exceeds the new result', () {
    final result = service.update(
      rawTranscript: 'new phrase',
      transcriptFloor: 3,
    );

    expect(result.resetFloor, isTrue);
    expect(result.transcriptFloor, 0);
    expect(result.freshWords, ['new', 'phrase']);
  });

  test(
    'browser cumulative snapshot restores unchanged earlier result slots',
    () {
      final result = service.update(
        rawTranscript: 'meeting founded in 20 22 more',
        transcriptFloor: 3,
        cumulativeReplacement: true,
        cumulativeBaselineWords: const ['meeting', 'founded', 'in'],
      );

      expect(result.resetFloor, isFalse);
      expect(result.transcriptFloor, 3);
      expect(result.freshWords, ['20', '22', 'more']);
      expect(result.recentSurfaceTranscript, '20 22 more');
    },
  );

  test('Whisper retraction preserves the acknowledged baseline', () {
    final result = service.update(
      rawTranscript: 'one two',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three'],
    );

    expect(result.resetFloor, isFalse);
    expect(result.transcriptFloor, 2);
    expect(result.freshWords, isEmpty);
  });

  test('Whisper retraction then regrowth does not replay consumed words', () {
    final retracted = service.update(
      rawTranscript: 'one two',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three'],
    );
    final regrown = service.update(
      rawTranscript: 'one two three four',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three'],
    );

    expect(retracted.freshWords, isEmpty);
    expect(regrown.transcriptFloor, 3);
    expect(regrown.freshWords, ['four']);
  });

  test('internal insertion before the boundary does not replay an anchor', () {
    final result = service.update(
      rawTranscript: 'one new two three four five',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three', 'four'],
    );

    expect(result.transcriptFloor, 4);
    expect(result.freshWords, ['four', 'five']);
  });

  test('internal deletion before the boundary does not skip the suffix', () {
    final result = service.update(
      rawTranscript: 'one three four five',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three', 'four'],
    );

    expect(result.transcriptFloor, 2);
    expect(result.freshWords, ['four', 'five']);
  });

  test('anchored substitution before the boundary remains consumed', () {
    final result = service.update(
      rawTranscript: 'one two revised four five',
      transcriptFloor: 4,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three', 'four', 'five'],
    );

    expect(result.transcriptFloor, 4);
    expect(result.freshWords, ['five']);
  });

  test('insertion exactly after the boundary remains fresh', () {
    final result = service.update(
      rawTranscript: 'one two three new four',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three', 'four'],
    );

    expect(result.transcriptFloor, 3);
    expect(result.freshWords, ['new', 'four']);
  });

  test('Hebrew repeated words map to the earliest stable boundary', () {
    final result = service.update(
      rawTranscript: 'של חדש של ישראל קדימה עוד',
      transcriptFloor: 2,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['של', 'של', 'ישראל', 'קדימה'],
    );

    expect(result.transcriptFloor, 3);
    expect(result.freshWords, ['ישראל', 'קדימה', 'עוד']);
  });

  test('ambiguous partial fails closed but phrase final can recover', () {
    final partial = service.update(
      rawTranscript: 'one two revised appended',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three'],
    );
    final phraseFinal = service.update(
      rawTranscript: 'one two revised appended',
      transcriptFloor: 3,
      cumulativeReplacement: true,
      cumulativeBaselineWords: const ['one', 'two', 'three'],
      cumulativeFinal: true,
    );

    expect(partial.freshWords, isEmpty);
    expect(phraseFinal.transcriptFloor, 2);
    expect(phraseFinal.freshWords, ['revised', 'appended']);
  });

  test(
    'keeps numeric surface punctuation without changing floor word counts',
    () {
      final result = service.update(
        rawTranscript: 'at 20:22 value 3.14 range 20-22 year 2022',
        transcriptFloor: 1,
        recentWordWindow: 20,
      );

      expect(result.spokenWords.length, 8);
      expect(result.freshWords.length, 7);
      expect(
        result.recentSurfaceTranscript,
        '20:22 value 3.14 range 20-22 year 2022',
      );
      expect(result.recentTranscript, '2022 value 314 range 2022 year 2022');
    },
  );
}
