import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tokenize keeps standalone opening bracket with following Hebrew word',
      () {
    final words = WordAligner.tokenize(
      '[ \u05d4\u05e4\u05e7\u05e1 \u05e9\u05dc \u05d4\u05de\u05d8\u05d1\u05d7 ]',
    ).where((word) => !word.isNewline).toList();

    expect(words.map((word) => word.raw), [
      '[\u05d4\u05e4\u05e7\u05e1',
      '\u05e9\u05dc',
      '\u05d4\u05de\u05d8\u05d1\u05d7]',
    ]);
  });

  test('tokenize skips standalone neutral punctuation words', () {
    final words = WordAligner.tokenize('... ! ?').toList();

    expect(words.where((word) => !word.isNewline), isEmpty);
  });

  test('tokenize keeps visual camera cues visible optional and speakable', () {
    final words = WordAligner.tokenize(
      '[r][LOOK DIRECTLY AT CAMERA B][/r]\nIf you speed up it speeds up',
    ).where((word) => !word.isNewline).toList();

    expect(words.take(5).map((word) => word.raw), [
      '[LOOK',
      'DIRECTLY',
      'AT',
      'CAMERA',
      'B]',
    ]);
    expect(words.take(5).map((word) => word.normalized), [
      'look',
      'directly',
      'at',
      'camera',
      'b',
    ]);
    expect(words.take(5).every((word) => word.isOptionalCue), isTrue);
  });

  test('alignment skips visual camera cues when reading continues below them',
      () {
    final words = WordAligner.tokenize(
      'With AutoTeleprompter your script listens to your voice.\n'
      '[r][LOOK DIRECTLY AT CAMERA B][/r]\n'
      'If you speed up it speeds up',
    );
    final result = WordAligner.align(
      script: words,
      transcript: 'if you speed up',
      lastConfirmedIndex: 7,
      maxSkipTargetIndex: words.length - 1,
    );

    expect(result.confirmedWordIndex, greaterThan(7));
    expect(words[result.confirmedWordIndex].normalized, 'up');
  });

  test('alignment can advance through a spoken visual camera cue', () {
    final words = WordAligner.tokenize(
      'With AutoTeleprompter your script listens to your voice.\n'
      '[r][LOOK DIRECTLY AT CAMERA B][/r]\n'
      'If you speed up it speeds up',
    );
    final result = WordAligner.align(
      script: words,
      transcript: 'look directly at camera b',
      lastConfirmedIndex: 7,
    );

    expect(result.confirmedWordIndex, greaterThan(7));
    expect(words[result.confirmedWordIndex].normalized, 'b');
    expect(words[result.confirmedWordIndex].isOptionalCue, isTrue);
  });
}
