import 'package:autoteleprompter/features/teleprompter/services/spoken_number_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

SpokenNumberSpan _singleSpan(String text) {
  final spans = SpokenNumberNormalizer.scan(
    SpokenNumberNormalizer.surfaceTokens(text),
  );
  expect(spans, hasLength(1), reason: 'Expected one number span for "$text"');
  return spans.single;
}

List<SpokenNumberSpan> _spans(String text) =>
    SpokenNumberNormalizer.scan(SpokenNumberNormalizer.surfaceTokens(text));

void main() {
  group('English whole-number normalization', () {
    test('parses digits and cardinal readings of 2022', () {
      final digits = _singleSpan('2022');
      expect(digits.value.integer, 2022);
      expect(digits.value.exactDigits, '2022');
      expect(digits.source, SpokenNumberSource.digits);

      for (final phrase in [
        'two thousand twenty two',
        'two thousand and twenty-two',
      ]) {
        final spoken = _singleSpan(phrase);
        expect(spoken.value.integer, 2022, reason: phrase);
        expect(spoken.value.kind, SpokenNumberKind.cardinal, reason: phrase);
        expect(spoken.source, SpokenNumberSource.englishWords);
        expect(spoken.value.equivalentTo(digits.value), isTrue);
      }
    });

    test('parses year-style and digit-by-digit readings', () {
      final year = _singleSpan('twenty twenty two');
      expect(year.value.integer, 2022);
      expect(year.value.kind, SpokenNumberKind.year);

      for (final phrase in ['two zero two two', 'two oh two two']) {
        final sequence = _singleSpan(phrase);
        expect(sequence.value.integer, 2022, reason: phrase);
        expect(sequence.value.exactDigits, '2022', reason: phrase);
        expect(
          sequence.value.kind,
          SpokenNumberKind.digitSequence,
          reason: phrase,
        );
      }
    });

    test(
      'accepts split and hyphenated values without changing their value',
      () {
        final split = _singleSpan('twenty two');
        final hyphenated = _singleSpan('twenty-two');
        expect(split.value.integer, 22);
        expect(hyphenated.value.integer, 22);
        expect(split.value.equivalentTo(hyphenated.value), isTrue);
      },
    );

    test('does not treat an incomplete 2022 reading as 2022', () {
      expect(_singleSpan('two thousand').value.integer, 2000);
      expect(_singleSpan('twenty twenty').value.integer, 2020);
    });
  });

  group('Hebrew whole-number normalization', () {
    test('parses gender and conjunction variants of 2022', () {
      for (final phrase in [
        'אלפיים עשרים ושתיים',
        'אלפיים עשרים ושניים',
        'אלפיים ועשרים ושתיים',
        'אלפיים ועשרים ושניים',
      ]) {
        final spoken = _singleSpan(phrase);
        expect(spoken.value.integer, 2022, reason: phrase);
        expect(spoken.value.kind, SpokenNumberKind.cardinal, reason: phrase);
        expect(spoken.source, SpokenNumberSource.hebrewWords);
      }
    });

    test('parses masculine and feminine digit-by-digit readings', () {
      for (final phrase in ['שתיים אפס שתיים שתיים', 'שניים אפס שניים שניים']) {
        final sequence = _singleSpan(phrase);
        expect(sequence.value.integer, 2022, reason: phrase);
        expect(sequence.value.exactDigits, '2022', reason: phrase);
        expect(
          sequence.value.kind,
          SpokenNumberKind.digitSequence,
          reason: phrase,
        );
      }
    });

    test('does not treat an incomplete 2022 reading as 2022', () {
      expect(_singleSpan('אלפיים').value.integer, 2000);
      expect(_singleSpan('אלפיים עשרים').value.integer, 2020);
    });

    test('parses a colloquial split year only in transcript mode', () {
      for (final phrase in [
        'עשרים עשרים ושתיים',
        'עשרים עשרים ושניים',
        'עשרים אפס חמש',
      ]) {
        expect(_spans(phrase), isEmpty, reason: phrase);
        final spans = SpokenNumberNormalizer.scan(
          SpokenNumberNormalizer.surfaceTokens(phrase),
          allowYearPairs: true,
        );
        expect(spans, hasLength(1), reason: phrase);
        expect(
          spans.single.value.integer,
          phrase.endsWith('חמש') ? 2005 : 2022,
          reason: phrase,
        );
        expect(
          spans.single.value.kind,
          SpokenNumberKind.yearPair,
          reason: phrase,
        );
        expect(spans.single.source, SpokenNumberSource.hebrewWords);
      }
    });
  });

  group('cross-language semantic equivalence', () {
    test('Hebrew, English, and digits share the same numeric value', () {
      final digits = _singleSpan('2022').value;
      final englishCardinal = _singleSpan('two thousand twenty two').value;
      final englishYear = _singleSpan('twenty twenty two').value;
      final hebrewCardinal = _singleSpan('אלפיים עשרים ושתיים').value;
      final hebrewDigits = _singleSpan('שתיים אפס שתיים שתיים').value;

      for (final value in [
        englishCardinal,
        englishYear,
        hebrewCardinal,
        hebrewDigits,
      ]) {
        expect(value.equivalentTo(digits), isTrue);
        expect(digits.equivalentTo(value), isTrue);
      }
    });
  });

  group('unsafe structure and leading-zero safety', () {
    test('parses unpunctuated digit year pairs only in transcript mode', () {
      expect(_spans('20 22'), isEmpty);
      for (final testCase in [('20 22', 2022), ('20 05', 2005)]) {
        final spans = SpokenNumberNormalizer.scan(
          SpokenNumberNormalizer.surfaceTokens(testCase.$1),
          allowYearPairs: true,
        );
        expect(spans, hasLength(1), reason: testCase.$1);
        expect(spans.single.value.integer, testCase.$2);
        expect(spans.single.value.kind, SpokenNumberKind.yearPair);
        expect(spans.single.source, SpokenNumberSource.digits);
      }
    });

    test('year-pair mode still rejects explicit ranges dates and times', () {
      for (final unsafe in [
        '20-22',
        '20 - 22',
        '20:22',
        '20 : 22',
        '20/22',
        '20 / 22',
        'עשרים - עשרים ושתיים',
      ]) {
        final spans = SpokenNumberNormalizer.scan(
          SpokenNumberNormalizer.surfaceTokens(unsafe),
          allowYearPairs: true,
        );
        expect(spans, isEmpty, reason: unsafe);
      }
    });

    test('year-pair mode rejects weak or out-of-range pairs', () {
      for (final unsafe in [
        '20 2',
        '30 22',
        '2000 22',
        'עשרים שתיים',
        'עשרים ועשרים ושתיים',
        'עשרים ואפס חמש',
      ]) {
        final spans = SpokenNumberNormalizer.scan(
          SpokenNumberNormalizer.surfaceTokens(unsafe),
          allowYearPairs: true,
        );
        expect(
          spans.any((span) => span.value.integer == 2022),
          isFalse,
          reason: unsafe,
        );
      }
    });

    test('does not collapse structured or signed values into 2022', () {
      for (final unsafe in [
        '20:22',
        '20/22',
        '20-22',
        '20–22',
        '2.022',
        '-2022',
        '+2022',
        r'2022%',
        r'2022$',
      ]) {
        final spans = SpokenNumberNormalizer.scan(
          SpokenNumberNormalizer.surfaceTokens(unsafe),
        );
        expect(spans, isEmpty, reason: unsafe);
      }
    });

    test('preserves leading zeroes for exact digit-sequence comparison', () {
      final leadingZero = _singleSpan('02022').value;
      final plainDigits = _singleSpan('2022').value;
      final cardinal = _singleSpan('two thousand twenty two').value;

      expect(leadingZero.integer, 2022);
      expect(leadingZero.exactDigits, '02022');
      expect(leadingZero.kind, SpokenNumberKind.digitSequence);
      expect(leadingZero.equivalentTo(plainDigits), isFalse);
      expect(plainDigits.equivalentTo(leadingZero), isFalse);
      expect(leadingZero.equivalentTo(cardinal), isFalse);
    });

    test('adjacent punctuated values stay unavailable as partial anchors', () {
      final spans = SpokenNumberNormalizer.scan(
        SpokenNumberNormalizer.surfaceTokens('twenty, twenty-two'),
      );
      expect(spans, isEmpty);
    });

    test('trailing sentence punctuation is safe for a plain number', () {
      final span = _singleSpan('2022,');
      expect(span.value.integer, 2022);
      expect(span.value.exactDigits, '2022');
    });
  });

  group('reviewed grammar regressions', () {
    test('parses Hebrew construct forms of twelve', () {
      for (final phrase in ['שנים עשר', 'שתים עשרה']) {
        final span = _singleSpan(phrase);
        expect(span.value.integer, 12, reason: phrase);
        expect(span.source, SpokenNumberSource.hebrewWords, reason: phrase);
      }
    });

    test('parses nineteen oh five as the year 1905', () {
      final span = _singleSpan('nineteen oh five');
      expect(span.value.integer, 1905);
      expect(span.value.kind, SpokenNumberKind.year);
      expect(span.source, SpokenNumberSource.englishWords);
    });

    test('rejects a full malformed or repeated scale span', () {
      for (final malformed in [
        'one thousand thousand',
        'one million million',
        'one thousand one million',
        'אלף אלף',
        'אלף מיליון',
      ]) {
        final tokenCount =
            SpokenNumberNormalizer.surfaceTokens(malformed).length;
        final hasFullSpan = _spans(
          malformed,
        ).any((span) => span.start == 0 && span.endExclusive == tokenCount);
        expect(hasFullSpan, isFalse, reason: malformed);
      }

      expect(_singleSpan('one million one thousand').value.integer, 1001000);
      expect(_singleSpan('מיליון אלף').value.integer, 1001000);
    });

    test('numeric modifiers cannot expose a plain 2022 span', () {
      for (final modified in [
        r'$2022',
        '₪2022',
        '%2022',
        '2022%',
        r'$ 2022',
        r'2022 $',
        'percent 2022',
        '2022 percent',
        'minus 2022',
        'negative 2022',
        '2022 point zero five',
        'שקל 2022',
        '2022 אחוז',
        '2022 נקודה חמש',
      ]) {
        final exposes2022 = _spans(
          modified,
        ).any((span) => span.value.integer == 2022);
        expect(exposes2022, isFalse, reason: modified);
      }
    });

    test('modifier-tainted phrases expose no shorter numeric prefix', () {
      for (final modified in [
        'two thousand twenty two percent',
        'two thousand twenty two dollars',
        'percent two thousand twenty two',
        'dollars two thousand twenty two',
        'אלפיים עשרים ושתיים אחוז',
        'אלפיים עשרים ושתיים שקלים',
        'אחוז אלפיים עשרים ושתיים',
        'שקלים אלפיים עשרים ושתיים',
      ]) {
        expect(_spans(modified), isEmpty, reason: modified);
      }
    });

    test('Unicode signs and ranges remain structurally unsafe', () {
      for (final unsafe in [
        '−2022',
        '‐2022',
        '20−22',
        '20–22',
        '20—22',
        '20־22',
      ]) {
        expect(_spans(unsafe), isEmpty, reason: unsafe);
      }
    });
  });

  group('reviewer numeric safety matrix', () {
    test('prefix and suffix modifiers taint the complete English phrase', () {
      for (final modified in [
        'negative twenty two',
        'twenty two negative',
        'minus two thousand twenty two',
        'two thousand twenty two minus',
        'percent two thousand twenty two',
        'two thousand twenty two percent',
        'dollar two thousand twenty two',
        'two thousand twenty two dollars',
      ]) {
        expect(_spans(modified), isEmpty, reason: modified);
      }
    });

    test('prefix and suffix modifiers taint the complete Hebrew phrase', () {
      for (final modified in [
        'מינוס עשרים ושתיים',
        'עשרים ושתיים מינוס',
        'אחוז אלפיים עשרים ושתיים',
        'אלפיים עשרים ושתיים אחוזים',
        'דולר אלפיים עשרים ושתיים',
        'אלפיים עשרים ושתיים דולרים',
        'שקל אלפיים עשרים ושתיים',
        'אלפיים עשרים ושתיים שקלים',
      ]) {
        expect(_spans(modified), isEmpty, reason: modified);
      }
    });

    for (final modified in ['שלילי עשרים ושתיים', 'עשרים ושתיים שלילי']) {
      test('Hebrew negative adjective taints "$modified"', () {
        expect(_spans(modified), isEmpty, reason: modified);
      });
    }

    test('spaced separators and signs cannot become adjacent numbers', () {
      for (final unsafe in [
        '20 : 22',
        '20 / 22',
        '20 - 22',
        '20 ‐ 22',
        '20 – 22',
        '20 — 22',
        '20 − 22',
        '20 ־ 22',
        '+ 2022',
        '- 2022',
        '− 2022',
        '2022 +',
        '2022 -',
        '2022 −',
      ]) {
        expect(_spans(unsafe), isEmpty, reason: unsafe);
      }
    });

    test('attached currency and percent symbols taint digits and words', () {
      for (final unsafe in [
        r'$2022',
        r'2022$',
        '€2022',
        '2022€',
        '£2022',
        '2022£',
        '₪2022',
        '2022₪',
        '%2022',
        '2022%',
        r'$twenty-two',
        r'twenty-two$',
        '€twenty two',
        'twenty two€',
        '£twenty-two',
        'twenty-two£',
        '₪אלפיים עשרים ושתיים',
        'אלפיים עשרים ושתיים₪',
      ]) {
        expect(_spans(unsafe), isEmpty, reason: unsafe);
      }
    });

    test('currency codes and names taint numbers on either side', () {
      for (final modified in [
        'EUR 2022',
        '2022 EUR',
        'GBP twenty two',
        'twenty two GBP',
        'NIS אלפיים עשרים ושתיים',
        'אלפיים עשרים ושתיים NIS',
        'euro twenty two',
        'twenty two euros',
        'pound twenty two',
        'twenty two pounds',
      ]) {
        expect(_spans(modified), isEmpty, reason: modified);
      }
    });

    test('leading trailing and internal numeric structure stays unsafe', () {
      for (final unsafe in [
        ':2022',
        '2022:',
        '/2022',
        '2022/',
        '-2022',
        '2022-',
        '–2022',
        '2022–',
        '−2022',
        '2022−',
        '20:22',
        '20/22',
        '20-22',
        '20–22',
        '20−22',
        '2.022',
        '2,022',
      ]) {
        expect(_spans(unsafe), isEmpty, reason: unsafe);
      }
    });

    test('non-whitelisted structure cannot collapse into a number', () {
      for (final unsafe in [
        '20+22',
        '20=22',
        '20_22',
        '20|22',
        '20×22',
        '3·14',
        '3. 14',
        '3 .14',
        '₹twenty two',
        'twenty+two',
      ]) {
        expect(_spans(unsafe), isEmpty, reason: unsafe);
      }
    });

    test('modifier punctuation cannot detach a clean number span', () {
      for (final modified in [
        'minus, twenty two',
        'USD, 2022',
        '2022 (percent)',
      ]) {
        expect(_spans(modified), isEmpty, reason: modified);
      }
    });

    test('accounting parentheses are not a positive number span', () {
      expect(_spans('(2022)'), isEmpty);
    });

    test(
      'ordinary conjunctions and Hebrew years words have no number intent',
      () {
        for (final ordinary in [
          'latest and lexical',
          'חדש ו מדויק',
          'שנים טובות',
          'ושנים',
        ]) {
          final surfaces = SpokenNumberNormalizer.surfaceTokens(ordinary);
          expect(_spans(ordinary), isEmpty, reason: ordinary);
          expect(
            SpokenNumberNormalizer.hasTailNumericIntent(surfaces),
            isFalse,
            reason: ordinary,
          );
        }
      },
    );

    test(
      'ordinary trailing conjunctions preserve the preceding number span',
      () {
        final english = _spans('2022 and welcome');
        expect(english, hasLength(1));
        expect(english.single.start, 0);
        expect(english.single.endExclusive, 1);
        expect(english.single.value.integer, 2022);

        final hebrew = _spans('אלפיים עשרים ושתיים ו ברוכים');
        expect(hebrew, hasLength(1));
        expect(hebrew.single.start, 0);
        expect(hebrew.single.endExclusive, 3);
        expect(hebrew.single.value.integer, 2022);
      },
    );

    test('sentence punctuation and lexical hyphens remain valid', () {
      final sentenceFinal = _singleSpan('2022.');
      final hyphenated = _singleSpan('twenty-two');

      expect(sentenceFinal.value.integer, 2022);
      expect(sentenceFinal.value.exactDigits, '2022');
      expect(hyphenated.value.integer, 22);
      expect(hyphenated.source, SpokenNumberSource.englishWords);
    });
  });
}
