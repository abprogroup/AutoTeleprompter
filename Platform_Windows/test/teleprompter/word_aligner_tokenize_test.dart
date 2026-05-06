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

  test('tokenize moves dash after RTL bracket punctuation to following word',
      () {
    final words = WordAligner.tokenize(
      '[\u05d0\u05e0\u05d9 \u05dc\u05d0 \u05d9\u05d5\u05e9\u05d1 \u05d1\u05e8\u05d0\u05e9 \u05d4\u05e9\u05d5\u05dc\u05d7\u05df?]- \u05d4\u05d9\u05dc\u05d3\u05d9\u05dd \u05d4\u05d0\u05dc\u05d4 \u05db\u05d1\u05e8 \u05e9\u05e0\u05d9\u05dd \u05dc\u05d0 \u05dc\u05d5\u05de\u05d3\u05d9\u05dd.',
    ).where((word) => !word.isNewline).toList();

    expect(words.map((word) => word.raw), [
      '[\u05d0\u05e0\u05d9',
      '\u05dc\u05d0',
      '\u05d9\u05d5\u05e9\u05d1',
      '\u05d1\u05e8\u05d0\u05e9',
      '\u05d4\u05e9\u05d5\u05dc\u05d7\u05df?]',
      '- \u05d4\u05d9\u05dc\u05d3\u05d9\u05dd',
      '\u05d4\u05d0\u05dc\u05d4',
      '\u05db\u05d1\u05e8',
      '\u05e9\u05e0\u05d9\u05dd',
      '\u05dc\u05d0',
      '\u05dc\u05d5\u05de\u05d3\u05d9\u05dd.',
    ]);
    expect(words[5].normalized, '\u05d4\u05d9\u05dc\u05d3\u05d9\u05dd');
  });

  test('tokenize keeps word-ending Hebrew dash attached to current word', () {
    final words = WordAligner.tokenize(
      '\u05d4\u05d9\u05d5\u05dd \u05d4\u05d6\u05d4 \u05de\u05de\u05e9- \u05d4\u05d9\u05dc\u05d3\u05d9\u05dd',
    ).where((word) => !word.isNewline).toList();

    expect(words.map((word) => word.raw), [
      '\u05d4\u05d9\u05d5\u05dd',
      '\u05d4\u05d6\u05d4',
      '\u05de\u05de\u05e9-',
      '\u05d4\u05d9\u05dc\u05d3\u05d9\u05dd',
    ]);
  });
}
