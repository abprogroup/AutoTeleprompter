/// The deliberately bounded number forms understood by live STT alignment.
/// Dates, times, ranges, decimals, signs, percentages, and currencies are not
/// included: treating their punctuation as decoration can turn `20:22` into
/// the unrelated year `2022`.
enum SpokenNumberKind { cardinal, year, yearPair, digitSequence }

enum SpokenNumberSource { digits, englishWords, hebrewWords }

class SpokenNumberValue {
  final int integer;
  final String? exactDigits;
  final SpokenNumberKind kind;

  const SpokenNumberValue({
    required this.integer,
    required this.kind,
    this.exactDigits,
  });

  bool equivalentTo(SpokenNumberValue other) {
    final thisHasLeadingZero =
        exactDigits != null &&
        exactDigits!.length > 1 &&
        exactDigits![0] == '0';
    final otherHasLeadingZero =
        other.exactDigits != null &&
        other.exactDigits!.length > 1 &&
        other.exactDigits![0] == '0';
    if (thisHasLeadingZero || otherHasLeadingZero) {
      return exactDigits != null && exactDigits == other.exactDigits;
    }
    return integer == other.integer;
  }

  String get debugLabel => exactDigits ?? integer.toString();
}

class SpokenNumberSpan {
  final int start;
  final int endExclusive;
  final SpokenNumberValue value;
  final SpokenNumberSource source;

  const SpokenNumberSpan({
    required this.start,
    required this.endExclusive,
    required this.value,
    required this.source,
  });
}
