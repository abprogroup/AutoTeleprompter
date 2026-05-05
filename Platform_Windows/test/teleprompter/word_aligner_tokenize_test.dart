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
}
