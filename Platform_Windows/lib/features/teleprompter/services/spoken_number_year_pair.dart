part of 'spoken_number_normalizer.dart';

/// Parses an unpunctuated colloquial year split such as `20 22` or
/// `עשרים עשרים ושתיים`. This is enabled only for heard transcript tokens;
/// normal script scanning keeps adjacent values separate and explicit range,
/// date, and time punctuation remains structurally unsafe.
(SpokenNumberValue, SpokenNumberSource)? _parseSpokenYearPair(
  List<String> words,
) {
  if (words.length < 2 || words.length > SpokenNumberNormalizer.maxSpanTokens) {
    return null;
  }

  if (words.length == 2 &&
      words.every((word) => RegExp(r'^\d{2}$').hasMatch(word))) {
    final first = int.parse(words.first);
    final second = int.parse(words.last);
    if (first >= 10 && first <= 29) {
      return (
        SpokenNumberValue(
          integer: first * 100 + second,
          kind: SpokenNumberKind.yearPair,
        ),
        SpokenNumberSource.digits,
      );
    }
    return null;
  }

  if (!words.every(SpokenNumberNormalizer._isHebrewNumberLexeme)) return null;
  SpokenNumberValue? match;
  for (var split = 1; split < words.length; split++) {
    final first = SpokenNumberNormalizer._parseHebrewCardinal(
      words.sublist(0, split),
    );
    final tail = words.sublist(split);
    final boundaryWord = tail.first;
    final strippedBoundaryWord =
        SpokenNumberNormalizer._stripKnownHebrewConjunction(boundaryWord);
    if (boundaryWord == 'ו' || strippedBoundaryWord != boundaryWord) {
      // A conjunction at the split means two coordinated numbers (for
      // example, "twenty and twenty-two"), not a colloquial year pair.
      continue;
    }
    final leadingZeroTail = tail.length == 2 && strippedBoundaryWord == 'אפס';
    final second =
        leadingZeroTail
            ? SpokenNumberNormalizer
                ._hebrewDigits[SpokenNumberNormalizer._stripKnownHebrewConjunction(
              tail.last,
            )]
            : SpokenNumberNormalizer._parseHebrewCardinal(tail);
    if (first == null || second == null || first < 10 || first > 29) continue;
    if ((second < 10 && !leadingZeroTail) || second > 99) continue;
    if (match != null) return null;
    match = SpokenNumberValue(
      integer: first * 100 + second,
      kind: SpokenNumberKind.yearPair,
    );
  }
  return match == null ? null : (match, SpokenNumberSource.hebrewWords);
}
