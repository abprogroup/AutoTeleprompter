import '../../script/models/script_word.dart';
import '../../../core/extensions/string_extensions.dart';

/// Ported from Windows as a new, available capability - fuzzy phrase search
/// over script words (Levenshtein-based). Used on Windows by the in-script
/// search dialog and the recording presenter tools (Milestone 7, not yet
/// ported). Android's existing search dialog (`teleprompter_screen.
/// bookmarks_search.dart`) does its own simpler matching today; wiring this
/// service into that dialog is a separate, follow-up piece of work, not part
/// of the STT movement-policy port - see `android_parity_gaps.md` #22.
class ApproximateSpokenSearchMatch {
  final int startWordIndex;
  final int endWordIndex;
  final double score;
  final String matchedText;

  const ApproximateSpokenSearchMatch({
    required this.startWordIndex,
    required this.endWordIndex,
    required this.score,
    required this.matchedText,
  });
}

class ApproximateSpokenSearchService {
  static final RegExp _tagPattern = RegExp(r'\[[^\]]+\]|\*\*');
  static const int _maxDirectQueryTokens = 16;
  static const int _longQueryWindowTokens = 12;
  static const int _shortLongQueryWindowTokens = 8;
  static const int _longQueryStride = 1;
  static const int _maxLongQueryVariants = 64;

  const ApproximateSpokenSearchService();

  ApproximateSpokenSearchMatch? findBest({
    required List<ScriptWord> words,
    required String spokenText,
    double? minimumScore,
  }) {
    final ranked = findRanked(
      words: words,
      spokenText: spokenText,
      minimumScore: minimumScore,
      limit: 1,
    );
    return ranked.isEmpty ? null : ranked.first;
  }

  List<ApproximateSpokenSearchMatch> findRanked({
    required List<ScriptWord> words,
    required String spokenText,
    double? minimumScore,
    int limit = 5,
  }) {
    if (limit <= 0) return const [];
    final queryTokens = tokenize(spokenText);
    if (queryTokens.isEmpty) return const [];
    final queryVariants = _queryVariants(queryTokens);
    if (queryVariants.isEmpty) return const [];

    final tokens = <_IndexedToken>[];
    for (final word in words) {
      if (word.isNewline) continue;
      for (final token in tokenize(word.raw)) {
        tokens.add(_IndexedToken(token, word.index));
      }
    }
    if (tokens.isEmpty) return const [];

    final candidates = <ApproximateSpokenSearchMatch>[];
    for (final variant in queryVariants) {
      final query = variant.tokens;
      final threshold = minimumScore ?? _minimumScoreFor(query.length);
      final minWindow = (query.length * 0.72).floor().clamp(1, query.length);
      final maxWindow =
          (query.length * 1.28).ceil().clamp(query.length, query.length + 8);

      for (var start = 0; start < tokens.length; start++) {
        for (var window = minWindow; window <= maxWindow; window++) {
          final end = start + window;
          if (end > tokens.length) break;
          final candidate = tokens.sublist(start, end);
          final rawScore = _tokenSimilarity(
            query,
            candidate.map((t) => t.text).toList(growable: false),
          );
          final score = (rawScore - variant.penalty).clamp(0.0, 1.0);
          if (score < threshold) continue;
          candidates.add(
            ApproximateSpokenSearchMatch(
              startWordIndex: candidate.first.wordIndex,
              endWordIndex: candidate.last.wordIndex,
              score: score,
              matchedText: candidate.map((t) => t.text).join(' '),
            ),
          );
        }
      }
    }

    candidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.startWordIndex.compareTo(b.startWordIndex);
    });
    final ranked = <ApproximateSpokenSearchMatch>[];
    for (final candidate in candidates) {
      if (ranked.any((match) => _overlaps(match, candidate))) continue;
      ranked.add(candidate);
      if (ranked.length >= limit) break;
    }
    return ranked;
  }

  static List<String> tokenize(String text) {
    final cleaned = text
        .replaceAll(_tagPattern, ' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[֑-ׇ]'), '');
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (final rune in cleaned.runes) {
      if (_isTokenRune(rune)) {
        buffer.writeCharCode(rune);
      } else if (buffer.isNotEmpty) {
        final token = buffer.toString().normalizeForMatching();
        if (token.isNotEmpty) tokens.add(token);
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) {
      final token = buffer.toString().normalizeForMatching();
      if (token.isNotEmpty) tokens.add(token);
    }
    return tokens;
  }

  static List<_QueryVariant> _queryVariants(List<String> tokens) {
    if (tokens.length <= _maxDirectQueryTokens) {
      return [_QueryVariant(tokens, 0)];
    }

    final variants = <_QueryVariant>[];
    void addWindow(int start, int length) {
      if (variants.length >= _maxLongQueryVariants) return;
      final safeStart = start.clamp(0, tokens.length - 1).toInt();
      final safeEnd = (safeStart + length).clamp(safeStart + 1, tokens.length);
      final window = tokens.sublist(safeStart, safeEnd);
      if (window.length < 4) return;
      if (variants.any((variant) => _sameTokens(variant.tokens, window))) {
        return;
      }
      variants.add(_QueryVariant(window, 0.02));
    }

    addWindow(tokens.length - _maxDirectQueryTokens, _maxDirectQueryTokens);
    addWindow(tokens.length - _longQueryWindowTokens, _longQueryWindowTokens);
    addWindow(
      tokens.length - _shortLongQueryWindowTokens,
      _shortLongQueryWindowTokens,
    );

    for (var start = 0;
        start < tokens.length && variants.length < _maxLongQueryVariants;
        start += _longQueryStride) {
      addWindow(start, _longQueryWindowTokens);
      addWindow(start, _shortLongQueryWindowTokens);
    }

    return variants;
  }

  static bool _isTokenRune(int rune) {
    return (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x0590 && rune <= 0x05FF);
  }

  static double _minimumScoreFor(int tokenCount) {
    if (tokenCount <= 2) return 0.94;
    if (tokenCount <= 5) return 0.84;
    return 0.76;
  }

  static double _tokenSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final previous = List<double>.generate(b.length + 1, (i) => i.toDouble());
    final current = List<double>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i.toDouble();
      for (var j = 1; j <= b.length; j++) {
        final substitution =
            previous[j - 1] + _substitutionCost(a[i - 1], b[j - 1]);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] = _min3(substitution, deletion, insertion);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }

    final maxLen = a.length > b.length ? a.length : b.length;
    return (1.0 - (previous[b.length] / maxLen)).clamp(0.0, 1.0);
  }

  static double _substitutionCost(String a, String b) {
    if (a == b) return 0;
    final similarity = _characterSimilarity(a, b);
    if (similarity >= 0.82) return 0.3;
    if (similarity >= 0.68) return 0.55;
    return 1;
  }

  static double _characterSimilarity(String a, String b) {
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1;
    return (1.0 - distance / maxLen).clamp(0.0, 1.0);
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = _min3Int(
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        );
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static double _min3(double a, double b, double c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }

  static int _min3Int(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }

  static bool _overlaps(
    ApproximateSpokenSearchMatch a,
    ApproximateSpokenSearchMatch b,
  ) {
    return a.startWordIndex <= b.endWordIndex &&
        b.startWordIndex <= a.endWordIndex;
  }

  static bool _sameTokens(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _IndexedToken {
  final String text;
  final int wordIndex;

  const _IndexedToken(this.text, this.wordIndex);
}

class _QueryVariant {
  final List<String> tokens;
  final double penalty;

  const _QueryVariant(this.tokens, this.penalty);
}
