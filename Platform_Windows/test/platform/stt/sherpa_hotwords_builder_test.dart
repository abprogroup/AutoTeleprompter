import 'package:autoteleprompter/platform/stt/sherpa_hotwords_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SherpaTokenVocab & SherpaHotwordsBuilder', () {
    test('tokenizes uppercase Zipformer2 EN words using tokens.txt', () {
      const tokensContent = '''
<blk> 0
<sos/eos> 1
<unk> 2
▁RIS 10
EN 11
▁ME 12
S 13
SI 14
AH 15
▁RA 16
LL 17
IES 18
''';
      final vocab = SherpaTokenVocab.fromContent(tokensContent);
      expect(vocab.uppercaseLatin, isTrue);
      expect(vocab.usesSentencePieceSpace, isTrue);

      final result = SherpaHotwordsBuilder.buildForVocab(
        vocab: vocab,
        words: const ['risen', 'Messiah', 'rallies.', 'unknownxyz'],
        locale: 'en_US',
      );
      expect(result.wordCount, 3);
      expect(
        result.text.split('\n'),
        ['▁RIS EN', '▁ME S SI AH', '▁RA LL IES'],
      );
    });

    test('tokenizes lowercase Parakeet and Hebrew words accurately', () {
      const tokensContent = '''
<unk> 0
▁mes 10
si 11
ah 12
▁שלום 13
▁ישראל 14
''';
      final vocab = SherpaTokenVocab.fromContent(tokensContent);
      expect(vocab.uppercaseLatin, isFalse);

      final en = SherpaHotwordsBuilder.buildForVocab(
        vocab: vocab,
        words: const ['Messiah', 'שלום'],
        locale: 'en_US',
      );
      expect(en.wordCount, 1);
      expect(en.text, '▁mes si ah');

      final he = SherpaHotwordsBuilder.buildForVocab(
        vocab: vocab,
        words: const ['שָׁלוֹם!', 'ישראל'],
        locale: 'he_IL',
      );
      expect(he.wordCount, 2);
      expect(he.text.split('\n'), ['▁שלום', '▁ישראל']);
    });

    test('prioritizes upcoming script words from startIndex and filters stop words', () {
      final selected = SherpaHotwordsBuilder.selectScriptWords(
        const ['intro', 'the', 'and', 'risen', 'Messiah', 'rallies', 'Messiah'],
        startIndex: 3,
        maxWords: 3,
      );
      expect(selected, ['risen', 'Messiah', 'rallies']);
    });
  });
}
