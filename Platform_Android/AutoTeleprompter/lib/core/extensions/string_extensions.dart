extension HebrewNormalization on String {
  /// Detect if this string is predominantly Hebrew
  bool get isHebrew {
    if (isEmpty) return false;
    final hebrewChars = runes.where((r) => r >= 0x0590 && r <= 0x05FF).length;
    return hebrewChars / length > 0.2;
  }

  /// Strip Hebrew diacritics: nikud (U+05B0-U+05C7) and cantillation (U+0591-U+05AF)
  String stripHebrewDiacritics() {
    return replaceAll(RegExp(r'[\u0591-\u05C7]'), '');
  }

  /// Strip common Hebrew prefix letters that attach without spaces:
  /// ו (and), ה (the), ב (in), ל (to), מ (from), כ (like), ש (that)
  /// Also handles multi-prefix combos: ובה, ולה, מה, שב, etc.
  String stripHebrewPrefixes() {
    const prefixes = [
      // Triple combos
      'ובה', 'ולה', 'ומה', 'וכה', 'ושה',
      'ובל', 'ומל', 'וכל',
      // Double combos
      'וה', 'בה', 'לה', 'מה', 'כה', 'שה',
      'וב', 'ול', 'ומ', 'וכ', 'וש',
      'שב', 'של', 'שמ', 'שכ',
      'כש', 'לכ', 'מב',
      // Single
      'ו', 'ה', 'ב', 'ל', 'מ', 'כ', 'ש',
    ];
    for (final p in prefixes) {
      if (startsWith(p) && length - p.length >= 2) {
        return substring(p.length);
      }
    }
    return this;
  }

  /// Normalize a word for matching: strip diacritics, punctuation, lowercase
  /// Keeps digits so numbers like "96" can be matched by the aligner.
  String normalizeForMatching() {
    if (isHebrew) {
      return stripHebrewDiacritics()
          .replaceAll(RegExp(r'[^\u05D0-\u05EA\u05F0-\u05F40-9]'), '')
          .trim();
    }
    return toLowerCase().replaceAll(RegExp(r"[^a-z0-9']"), '').trim();
  }

  /// Compute Levenshtein edit distance
  int editDistance(String other) {
    if (this == other) return 0;
    if (isEmpty) return other.length;
    if (other.isEmpty) return length;

    final List<int> prev = List.generate(other.length + 1, (i) => i);
    final List<int> curr = List.filled(other.length + 1, 0);

    for (int i = 1; i <= length; i++) {
      curr[0] = i;
      for (int j = 1; j <= other.length; j++) {
        final cost = this[i - 1] == other[j - 1] ? 0 : 1;
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
      prev.setAll(0, curr);
    }
    return curr[other.length];
  }

  /// Similarity score 0.0–1.0 between this and other
  double similarity(String other) {
    if (this == other) return 1.0;
    if (isEmpty && other.isEmpty) return 1.0;
    final maxLen = length > other.length ? length : other.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (editDistance(other) / maxLen);
  }
}
