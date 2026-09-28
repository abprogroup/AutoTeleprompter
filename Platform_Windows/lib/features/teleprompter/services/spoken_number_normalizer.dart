import '../../../core/extensions/string_extensions.dart';
import 'spoken_number_types.dart';

export 'spoken_number_types.dart';

part 'spoken_number_year_pair.dart';

/// Deterministic Hebrew/English whole-number parser used only by alignment.
///
/// It never mutates transcript or script tokens, and never performs fuzzy
/// numeric matching. The longest valid span wins, capped at eight source
/// tokens and 999,999,999.
class SpokenNumberNormalizer {
  static const int maxSpanTokens = 8;
  static const int maxValue = 999999999;

  static List<String> surfaceTokens(String text) => text
      .trim()
      .split(RegExp(r'\s+'))
      .where((token) => token.trim().isNotEmpty)
      .toList(growable: false);

  static List<SpokenNumberSpan> scan(
    List<String> surfaceTokens, {
    bool allowYearPairs = false,
  }) {
    if (surfaceTokens.isEmpty) return const [];
    final atoms = surfaceTokens.map(_NumberAtom.fromSurface).toList();
    final spans = <SpokenNumberSpan>[];
    var cursor = 0;
    while (cursor < atoms.length) {
      if (!_participatesInNumericRunAt(atoms, cursor)) {
        cursor++;
        continue;
      }

      final runStart = cursor;
      var runEnd = cursor;
      var tainted = false;
      while (runEnd < atoms.length) {
        final atom = atoms[runEnd];
        if (runEnd > runStart &&
            !_numericAtomsConnected(atoms, runEnd - 1, runEnd)) {
          break;
        }
        if (!_participatesInNumericRunAt(atoms, runEnd)) break;
        tainted =
            tainted ||
            atom.numericModifier ||
            atom.structurallyUnsafe ||
            (runEnd > runStart &&
                _boundaryCarriesNumericStructure(atoms[runEnd - 1], atom));
        runEnd++;
      }

      final runLength = runEnd - runStart;
      if (!tainted && runLength <= maxSpanTokens) {
        final words = [for (var i = runStart; i < runEnd; i++) atoms[i].lexeme];
        final parsed = _parseExact(words, allowYearPairs: allowYearPairs);
        if (parsed != null) {
          spans.add(
            SpokenNumberSpan(
              start: runStart,
              endExclusive: runEnd,
              value: parsed.$1,
              source: parsed.$2,
            ),
          );
        }
      }
      cursor = runEnd > cursor ? runEnd : cursor + 1;
    }
    return spans;
  }

  /// Whether a number-like expression still belongs to the current transcript
  /// tail, including deliberately unsupported signed, structured, currency,
  /// percentage, or decimal forms. Alignment uses this only as a fail-closed
  /// signal so generic word matching cannot silently step over an explicit
  /// wrong or unsafe number.
  static bool hasTailNumericIntent(List<String> surfaceTokens) {
    if (surfaceTokens.isEmpty) return false;
    final atoms = surfaceTokens.map(_NumberAtom.fromSurface).toList();
    final tail = atoms.length - 1;
    if (!_participatesInNumericRunAt(atoms, tail)) return false;

    var start = tail;
    while (start > 0 && _numericAtomsConnected(atoms, start - 1, start)) {
      start--;
    }
    for (var i = start; i <= tail; i++) {
      final atom = atoms[i];
      if (atom.numericModifier || atom.structurallyUnsafe) {
        if (_numericRunHasCore(atoms, start, tail + 1)) return true;
      }
      if (_isStandaloneNumberLexeme(atom.lexeme)) return true;
    }
    return false;
  }

  /// Expands a derived transcript window so it cannot expose only one side of
  /// a number phrase, sign, modifier, decimal, range, or time expression.
  static ({int start, int endExclusive}) expandSurfaceWindow(
    List<String> surfaceTokens,
    int rawStart,
    int rawEnd,
  ) {
    if (surfaceTokens.isEmpty) return (start: 0, endExclusive: 0);
    final atoms = surfaceTokens.map(_NumberAtom.fromSurface).toList();
    var start = rawStart.clamp(0, atoms.length).toInt();
    var end = rawEnd.clamp(start, atoms.length).toInt();
    while (start > 0 && _numericAtomsConnected(atoms, start - 1, start)) {
      start--;
    }
    while (end < atoms.length &&
        end > 0 &&
        _numericAtomsConnected(atoms, end - 1, end)) {
      end++;
    }
    return (start: start, endExclusive: end);
  }

  static bool _numericRunHasCore(List<_NumberAtom> atoms, int start, int end) {
    for (var i = start; i < end; i++) {
      if (_isStandaloneNumberLexeme(atoms[i].lexeme)) return true;
    }
    return false;
  }

  static bool _numericAtomsConnected(
    List<_NumberAtom> atoms,
    int leftIndex,
    int rightIndex,
  ) {
    if (leftIndex < 0 || rightIndex >= atoms.length) return false;
    if (!_participatesInNumericRunAt(atoms, leftIndex) ||
        !_participatesInNumericRunAt(atoms, rightIndex)) {
      return false;
    }
    final left = atoms[leftIndex];
    final right = atoms[rightIndex];
    if (!left.boundaryAfter && !right.boundaryBefore) return true;
    return _boundaryCarriesNumericStructure(left, right);
  }

  static bool _boundaryCarriesNumericStructure(
    _NumberAtom left,
    _NumberAtom right,
  ) =>
      left.numericModifier ||
      right.numericModifier ||
      left.structurallyUnsafe ||
      right.structurallyUnsafe ||
      left.ambiguousNumericSeparatorAfter ||
      left.softStandaloneSeparator ||
      right.softStandaloneSeparator;

  static bool _participatesInNumericRunAt(List<_NumberAtom> atoms, int index) {
    final atom = atoms[index];
    if (atom.softStandaloneSeparator) {
      final leftIsNumber =
          index > 0 && _isStandaloneNumberLexeme(atoms[index - 1].lexeme);
      final rightIsNumber =
          index + 1 < atoms.length &&
          _isStandaloneNumberLexeme(atoms[index + 1].lexeme);
      return (leftIsNumber && rightIsNumber) ||
          (index == 0 && atom.lexemeSurface == '.' && rightIsNumber);
    }
    if (atom.numericModifier || atom.structurallyUnsafe) return true;
    final word = atom.lexeme;
    final hebrewWord = _stripKnownHebrewConjunction(word);
    if (_isNumericConnector(word)) {
      return index > 0 &&
          index + 1 < atoms.length &&
          !atoms[index - 1].boundaryAfter &&
          !atom.boundaryBefore &&
          !atom.boundaryAfter &&
          !atoms[index + 1].boundaryBefore &&
          _isStandaloneNumberLexeme(atoms[index - 1].lexeme) &&
          _isStandaloneNumberLexeme(atoms[index + 1].lexeme);
    }
    if (_isHebrewConstructOnly(hebrewWord)) {
      if (index + 1 >= atoms.length || atom.boundaryAfter) return false;
      final next = _stripKnownHebrewConjunction(atoms[index + 1].lexeme);
      if (hebrewWord == 'שנים' || hebrewWord == 'שתים') {
        return next == 'עשר' || next == 'עשרה';
      }
      return hebrewWord == 'עשרת' && (next == 'אלף' || next == 'אלפים');
    }
    return _isStandaloneNumberLexeme(word);
  }

  static bool _isNumericConnector(String word) => word == 'and' || word == 'ו';

  static bool _isHebrewConstructOnly(String word) =>
      word == 'שנים' || word == 'שתים' || word == 'עשרת';

  static bool _isStandaloneNumberLexeme(String word) =>
      !_isNumericConnector(word) &&
      !_isHebrewConstructOnly(word) &&
      _isPotentialNumberLexeme(word);

  static bool _isPotentialNumberLexeme(String word) =>
      RegExp(r'^\d{1,9}$').hasMatch(word) ||
      _isEnglishNumberLexeme(word) ||
      _isHebrewNumberLexeme(word);

  static (SpokenNumberValue, SpokenNumberSource)? _parseExact(
    List<String> words, {
    bool allowYearPairs = false,
  }) {
    if (words.isEmpty) return null;
    if (allowYearPairs) {
      final yearPair = _parseSpokenYearPair(words);
      if (yearPair != null) return yearPair;
    }
    if (words.length == 1 && RegExp(r'^\d{1,9}$').hasMatch(words.single)) {
      final digits = words.single;
      final value = int.tryParse(digits);
      if (value == null || value > maxValue) return null;
      return (
        SpokenNumberValue(
          integer: value,
          exactDigits: digits,
          kind:
              digits.length > 1 && digits.startsWith('0')
                  ? SpokenNumberKind.digitSequence
                  : SpokenNumberKind.cardinal,
        ),
        SpokenNumberSource.digits,
      );
    }

    if (words.every(_isEnglishNumberLexeme)) {
      final digitSequence = _parseEnglishDigitSequence(words);
      if (digitSequence != null) {
        return (digitSequence, SpokenNumberSource.englishWords);
      }
      final year = _parseEnglishYear(words);
      if (year != null) return (year, SpokenNumberSource.englishWords);
      final cardinal = _parseEnglishCardinal(words);
      if (cardinal != null) {
        return (
          SpokenNumberValue(integer: cardinal, kind: SpokenNumberKind.cardinal),
          SpokenNumberSource.englishWords,
        );
      }
    }

    if (words.every(_isHebrewNumberLexeme)) {
      final digitSequence = _parseHebrewDigitSequence(words);
      if (digitSequence != null) {
        return (digitSequence, SpokenNumberSource.hebrewWords);
      }
      final cardinal = _parseHebrewCardinal(words);
      if (cardinal != null) {
        return (
          SpokenNumberValue(integer: cardinal, kind: SpokenNumberKind.cardinal),
          SpokenNumberSource.hebrewWords,
        );
      }
    }
    return null;
  }

  static SpokenNumberValue? _parseEnglishDigitSequence(List<String> words) {
    if (words.length < 3 || words.length > maxSpanTokens) return null;
    final digits = StringBuffer();
    for (final word in words) {
      final digit = _englishDigits[word];
      if (digit == null) return null;
      digits.write(digit);
    }
    return _digitSequenceValue(digits.toString());
  }

  static SpokenNumberValue? _parseHebrewDigitSequence(List<String> words) {
    if (words.length < 3 || words.length > maxSpanTokens) return null;
    final digits = StringBuffer();
    for (final raw in words) {
      final word = _stripKnownHebrewConjunction(raw);
      final digit = _hebrewDigits[word];
      if (digit == null) return null;
      digits.write(digit);
    }
    return _digitSequenceValue(digits.toString());
  }

  static SpokenNumberValue? _digitSequenceValue(String digits) {
    if (digits.length > 9) return null;
    final value = int.tryParse(digits);
    if (value == null || value > maxValue) return null;
    return SpokenNumberValue(
      integer: value,
      exactDigits: digits,
      kind: SpokenNumberKind.digitSequence,
    );
  }

  static SpokenNumberValue? _parseEnglishYear(List<String> words) {
    if (words.length < 2 || words.length > 4 || words.contains('and')) {
      return null;
    }
    for (var split = 1; split < words.length; split++) {
      final first = _parseEnglishUnder100(words.sublist(0, split));
      final second = _parseEnglishYearTail(words.sublist(split));
      if (first == null || second == null || first < 10 || first > 29) {
        continue;
      }
      // `twenty two` means 22, not 2002. Two-token year readings require
      // a two-digit second group: `nineteen eighty`, `twenty twenty`.
      if (words.length == 2 && second < 10) continue;
      final value = first * 100 + second;
      if (value < 1000 || value > 2999) continue;
      return SpokenNumberValue(integer: value, kind: SpokenNumberKind.year);
    }
    return null;
  }

  static int? _parseEnglishYearTail(List<String> words) {
    if (words.length == 2 && words.first == 'oh') {
      final unit = _englishDigits[words.last];
      if (unit != null && unit >= 0 && unit <= 9) return unit;
    }
    return _parseEnglishUnder100(words);
  }

  static int? _parseEnglishCardinal(List<String> rawWords) {
    if (rawWords.isEmpty) return null;
    final words = <String>[];
    for (var i = 0; i < rawWords.length; i++) {
      final word = rawWords[i];
      if (word == 'and') {
        if (i == 0 || i == rawWords.length - 1 || rawWords[i - 1] == 'and') {
          return null;
        }
        continue;
      }
      words.add(word);
    }
    if (words.isEmpty) return null;

    var total = 0;
    var remaining = words;
    for (final scale in const [('million', 1000000), ('thousand', 1000)]) {
      final index = remaining.indexOf(scale.$1);
      if (index < 0) continue;
      if (remaining.lastIndexOf(scale.$1) != index || index == 0) return null;
      final group = _parseEnglishUnder1000(remaining.sublist(0, index));
      if (group == null || group <= 0) return null;
      total += group * scale.$2;
      remaining = remaining.sublist(index + 1);
    }
    if (remaining.isNotEmpty) {
      final tail = _parseEnglishUnder1000(remaining);
      if (tail == null) return null;
      total += tail;
    }
    if (total < 0 || total > maxValue) return null;
    return total;
  }

  static int? _parseEnglishUnder1000(List<String> words) {
    if (words.isEmpty) return null;
    final hundredIndex = words.indexOf('hundred');
    if (hundredIndex < 0) return _parseEnglishUnder100(words);
    if (words.lastIndexOf('hundred') != hundredIndex || hundredIndex != 1) {
      return null;
    }
    final hundreds = _englishSmall[words.first];
    if (hundreds == null || hundreds < 1 || hundreds > 9) return null;
    if (words.length == 2) return hundreds * 100;
    final tail = _parseEnglishUnder100(words.sublist(2));
    if (tail == null) return null;
    return hundreds * 100 + tail;
  }

  static int? _parseEnglishUnder100(List<String> words) {
    if (words.isEmpty || words.length > 2) return null;
    if (words.length == 1) {
      final direct = _englishSmall[words.single] ?? _englishTens[words.single];
      if (direct != null) return direct;
      for (final entry in _englishTens.entries) {
        if (!words.single.startsWith(entry.key)) continue;
        final suffix = words.single.substring(entry.key.length);
        final unit = _englishSmall[suffix];
        if (unit != null && unit > 0 && unit < 10) return entry.value + unit;
      }
      return null;
    }
    final tens = _englishTens[words.first];
    final unit = _englishSmall[words.last];
    if (tens == null || unit == null || unit < 1 || unit > 9) return null;
    return tens + unit;
  }

  static int? _parseHebrewCardinal(List<String> rawWords) {
    if (rawWords.isEmpty) return null;
    final words = <String>[];
    for (var i = 0; i < rawWords.length; i++) {
      final raw = rawWords[i];
      if (raw == 'ו') {
        if (i == 0 || i == rawWords.length - 1 || rawWords[i - 1] == 'ו') {
          return null;
        }
        continue;
      }
      final word = _stripKnownHebrewConjunction(raw);
      final next =
          i + 1 < rawWords.length
              ? _stripKnownHebrewConjunction(rawWords[i + 1])
              : null;
      if ((word == 'שנים' || word == 'שתים') &&
          (next == 'עשר' || next == 'עשרה')) {
        words.add(word == 'שנים' ? 'שניים' : 'שתיים');
        continue;
      }
      if (word == 'עשרת' && (next == 'אלף' || next == 'אלפים')) {
        words.add('עשר');
        continue;
      }
      if (word == 'שנים' || word == 'שתים' || word == 'עשרת') return null;
      words.add(word);
    }

    var total = 0;
    var current = 0;
    var lastScale = maxValue + 1;
    var previousWasUnit = false;
    var previousWasTens = false;
    for (final word in words) {
      final unit = _hebrewUnits[word];
      if (unit != null) {
        if (previousWasUnit) return null;
        current += unit;
        previousWasUnit = true;
        previousWasTens = false;
        continue;
      }
      final tens = _hebrewTens[word];
      if (tens != null) {
        if (previousWasTens) return null;
        if (previousWasUnit && tens != 10) return null;
        current += tens;
        previousWasTens = true;
        previousWasUnit = false;
        continue;
      }
      if (word == 'מאה') {
        if (current != 0) return null;
        current = 100;
      } else if (word == 'מאתיים') {
        if (current != 0) return null;
        current = 200;
      } else if (word == 'מאות') {
        if (current < 3 || current > 10) return null;
        current *= 100;
      } else if (word == 'אלף' || word == 'אלפים') {
        if (1000 >= lastScale) return null;
        final multiplier = current == 0 ? 1 : current;
        if (multiplier > 999) return null;
        total += multiplier * 1000;
        current = 0;
        lastScale = 1000;
      } else if (word == 'אלפיים') {
        if (current != 0 || 1000 >= lastScale) return null;
        total += 2000;
        lastScale = 1000;
      } else if (word == 'מיליון' || word == 'מיליונים') {
        if (1000000 >= lastScale) return null;
        final multiplier = current == 0 ? 1 : current;
        if (multiplier > 999) return null;
        total += multiplier * 1000000;
        current = 0;
        lastScale = 1000000;
      } else {
        return null;
      }
      previousWasUnit = false;
      previousWasTens = false;
    }
    final value = total + current;
    if (value < 0 || value > maxValue) return null;
    return value;
  }

  static bool _isEnglishNumberLexeme(String word) =>
      word == 'and' ||
      word == 'hundred' ||
      word == 'thousand' ||
      word == 'million' ||
      _englishDigits.containsKey(word) ||
      _englishSmall.containsKey(word) ||
      _englishTens.containsKey(word) ||
      _isCompactEnglishUnder100(word);

  static bool _isCompactEnglishUnder100(String word) {
    for (final tens in _englishTens.keys) {
      if (!word.startsWith(tens)) continue;
      final unit = word.substring(tens.length);
      final value = _englishSmall[unit];
      if (value != null && value > 0 && value < 10) return true;
    }
    return false;
  }

  static bool _isHebrewNumberLexeme(String raw) {
    if (raw == 'ו') return true;
    final word = _stripKnownHebrewConjunction(raw);
    return _knownHebrewLexemes.contains(word);
  }

  static String _stripKnownHebrewConjunction(String word) {
    if (word.length <= 1 || !word.startsWith('ו')) return word;
    final remainder = word.substring(1);
    return _knownHebrewLexemes.contains(remainder) ? remainder : word;
  }

  static const Map<String, int> _englishDigits = {
    'zero': 0,
    'oh': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
  };

  static const Map<String, int> _englishSmall = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const Map<String, int> _englishTens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  static const Map<String, int> _hebrewDigits = {
    'אפס': 0,
    'אחד': 1,
    'אחת': 1,
    'שניים': 2,
    'שתיים': 2,
    'שני': 2,
    'שתי': 2,
    'שלוש': 3,
    'שלושה': 3,
    'ארבע': 4,
    'ארבעה': 4,
    'חמש': 5,
    'חמישה': 5,
    'שש': 6,
    'שישה': 6,
    'שבע': 7,
    'שבעה': 7,
    'שמונה': 8,
    'תשע': 9,
    'תשעה': 9,
  };

  static const Map<String, int> _hebrewUnits = {
    ..._hebrewDigits,
    'שלושת': 3,
    'ארבעת': 4,
    'חמשת': 5,
    'ששת': 6,
    'שבעת': 7,
    'שמונת': 8,
    'תשעת': 9,
  };

  static const Map<String, int> _hebrewTens = {
    'עשר': 10,
    'עשרה': 10,
    'עשרים': 20,
    'שלושים': 30,
    'ארבעים': 40,
    'חמישים': 50,
    'שישים': 60,
    'שבעים': 70,
    'שמונים': 80,
    'תשעים': 90,
  };

  static final Set<String> _knownHebrewLexemes = {
    ..._hebrewUnits.keys,
    ..._hebrewTens.keys,
    'מאה',
    'מאתיים',
    'מאות',
    'אלף',
    'אלפיים',
    'אלפים',
    'מיליון',
    'מיליונים',
    'שנים',
    'שתים',
    'עשרת',
  };
}

class _NumberAtom {
  final String lexeme;
  final bool boundaryBefore;
  final bool boundaryAfter;
  final bool structurallyUnsafe;
  final bool numericModifier;
  final bool ambiguousNumericSeparatorAfter;
  final bool softStandaloneSeparator;
  final String lexemeSurface;

  const _NumberAtom({
    required this.lexeme,
    required this.boundaryBefore,
    required this.boundaryAfter,
    required this.structurallyUnsafe,
    required this.numericModifier,
    required this.ambiguousNumericSeparatorAfter,
    required this.softStandaloneSeparator,
    required this.lexemeSurface,
  });

  factory _NumberAtom.fromSurface(String surface) {
    var raw =
        surface.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '').trim().toLowerCase();
    if (raw.isEmpty) {
      return const _NumberAtom(
        lexeme: '',
        boundaryBefore: true,
        boundaryAfter: true,
        structurallyUnsafe: false,
        numericModifier: false,
        ambiguousNumericSeparatorAfter: false,
        softStandaloneSeparator: false,
        lexemeSurface: '',
      );
    }

    final modifierKey = raw.normalizeForMatching();
    final currencyOrPercent = RegExp(
      r'[\u0024\u00A3\u00A5\u20AA\u20AC%]',
    ).hasMatch(raw);
    final numericModifier =
        currencyOrPercent || _isNumericModifierWord(modifierKey);
    final surfaceForm = raw;
    final boundaryBefore = RegExp(
      r'''^[\[\(\{,;.!?"']''',
    ).hasMatch(surfaceForm);
    final boundaryAfter = RegExp(r'''[\]\)\},;.!?"']$''').hasMatch(surfaceForm);
    raw = raw
        .replaceFirst(RegExp(r'''^[\[\(\{,;.!?"']+'''), '')
        .replaceFirst(RegExp(r'''[\]\)\},;.!?"']+$'''), '');
    final lexeme = raw.normalizeForMatching();
    final legitimateEnglishHyphen =
        RegExp(r'^[a-z]+-[a-z]+$').hasMatch(surfaceForm) &&
        SpokenNumberNormalizer._isCompactEnglishUnder100(lexeme);
    final softStandaloneSeparator = RegExp(r'^[\.,;]$').hasMatch(surfaceForm);
    final standaloneStructure =
        lexeme.isEmpty && surfaceForm.isNotEmpty && !softStandaloneSeparator;
    final potentialNumber = SpokenNumberNormalizer._isPotentialNumberLexeme(
      lexeme,
    );
    final ambiguousNumericSeparatorAfter =
        potentialNumber && RegExp(r'[\.,]$').hasMatch(surfaceForm);
    final validNumericShape =
        RegExp(r'^\d{1,9}$').hasMatch(lexeme)
            ? RegExp(r'^\d{1,9}$').hasMatch(raw)
            : SpokenNumberNormalizer._isEnglishNumberLexeme(lexeme)
            ? RegExp(r'^[a-z]+$').hasMatch(raw) || legitimateEnglishHyphen
            : SpokenNumberNormalizer._isHebrewNumberLexeme(lexeme)
            ? RegExp(r'^[\u0591-\u05C7\u05D0-\u05EA]+$').hasMatch(raw)
            : true;
    final hardStructure =
        surfaceForm.contains(':') ||
        surfaceForm.contains('/') ||
        RegExp(r'[\u05BE\u2010-\u2015\u2212]').hasMatch(surfaceForm) ||
        (surfaceForm.contains('-') && !legitimateEnglishHyphen) ||
        surfaceForm.startsWith('+') ||
        ((surfaceForm.startsWith('.') || surfaceForm.startsWith(',')) &&
            surfaceForm.length > 1) ||
        RegExp(r'.+[\.,].+').hasMatch(surfaceForm);
    final unsafe =
        standaloneStructure ||
        currencyOrPercent ||
        (potentialNumber && RegExp(r'^\(.*\)$').hasMatch(surfaceForm)) ||
        (potentialNumber && !validNumericShape) ||
        (hardStructure &&
            (lexeme.isEmpty ||
                SpokenNumberNormalizer._isPotentialNumberLexeme(lexeme)));
    return _NumberAtom(
      lexeme: lexeme,
      boundaryBefore: standaloneStructure ? false : boundaryBefore,
      boundaryAfter: standaloneStructure ? false : boundaryAfter,
      structurallyUnsafe: unsafe,
      numericModifier: numericModifier,
      ambiguousNumericSeparatorAfter: ambiguousNumericSeparatorAfter,
      softStandaloneSeparator: softStandaloneSeparator,
      lexemeSurface: surfaceForm,
    );
  }

  static bool _isNumericModifierWord(String key) {
    if (_numericModifierWords.contains(key)) return true;
    if (key.length <= 1) return false;
    final first = key[0];
    return (first == 'ו' || first == 'ב' || first == 'כ' || first == 'ל') &&
        _numericModifierWords.contains(key.substring(1));
  }

  static const Set<String> _numericModifierWords = {
    'percent',
    'percentage',
    'pct',
    'per',
    'cent',
    'cents',
    'dollar',
    'dollars',
    'usd',
    'cad',
    'chf',
    'jpy',
    'eur',
    'gbp',
    'nis',
    'shekel',
    'shekels',
    'ils',
    'euro',
    'euros',
    'pound',
    'pounds',
    'yen',
    'rupee',
    'rupees',
    'point',
    'dot',
    'decimal',
    'plus',
    'minus',
    'negative',
    'אחוז',
    'אחוזים',
    'דולר',
    'דולרים',
    'שקל',
    'שקלים',
    'נקודה',
    'פסיק',
    'מינוס',
    'שלילי',
    'שלילית',
    'שח',
  };
}
