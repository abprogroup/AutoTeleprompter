import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';
import 'approximate_spoken_search_service.dart';
import 'word_aligner.dart';

class SttVisibleRelockService {
  const SttVisibleRelockService();

  int? exactPhraseTarget({
    required List<ScriptWord> words,
    required String transcript,
    required int currentIndex,
    required int? visibleWordStart,
    required int? visibleWordEnd,
    int minWords = 3,
  }) {
    if (visibleWordStart == null || visibleWordEnd == null) return null;
    final tokens = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final safeMinWords = minWords.clamp(3, 8).toInt();
    if (tokens.length < safeMinWords) return null;

    final start =
        visibleWordStart <= visibleWordEnd ? visibleWordStart : visibleWordEnd;
    final end =
        visibleWordStart <= visibleWordEnd ? visibleWordEnd : visibleWordStart;
    final visibleWords = words
        .where((word) =>
            !word.isNewline &&
            word.normalized.isNotEmpty &&
            word.index > currentIndex &&
            word.index >= start &&
            word.index <= end)
        .toList(growable: false);
    if (visibleWords.length < safeMinWords) return null;

    final maxPhrase = tokens.length < 8 ? tokens.length : 8;
    for (var phraseLen = maxPhrase; phraseLen >= safeMinWords; phraseLen--) {
      final phrase = tokens.sublist(tokens.length - phraseLen);
      final maxStart = visibleWords.length - phraseLen;
      for (var i = 0; i <= maxStart; i++) {
        var matched = true;
        for (var j = 0; j < phraseLen; j++) {
          if (visibleWords[i + j].normalized != phrase[j]) {
            matched = false;
            break;
          }
        }
        if (matched) return visibleWords[i + phraseLen - 1].index;
      }
    }

    return null;
  }

  int? fuzzyTarget({
    required List<ScriptWord> words,
    required String transcript,
    required int? visibleWordStart,
    required int? visibleWordEnd,
  }) {
    final tokens = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList();
    if (tokens.length < 4) return null;

    final realWords = words
        .where((word) => !word.isNewline && word.normalized.isNotEmpty)
        .toList();
    if (realWords.length < 4) return null;

    final hasVisibleWindow = visibleWordStart != null && visibleWordEnd != null;
    final visibleStart = !hasVisibleWindow
        ? null
        : visibleWordStart <= visibleWordEnd
            ? visibleWordStart
            : visibleWordEnd;
    final visibleEnd = !hasVisibleWindow
        ? null
        : visibleWordStart <= visibleWordEnd
            ? visibleWordEnd
            : visibleWordStart;
    final searchStart = visibleStart == null
        ? 0
        : realWords.indexWhere((word) => word.index >= visibleStart);
    if (searchStart < 0) return null;
    final searchEnd = visibleEnd == null
        ? realWords.length - 1
        : realWords.lastIndexWhere((word) => word.index <= visibleEnd);
    if (searchEnd < searchStart) return null;

    final maxPhrase = tokens.length < 8 ? tokens.length : 8;
    for (var phraseLen = maxPhrase; phraseLen >= 4; phraseLen--) {
      final maxStart = searchEnd - phraseLen + 1;
      if (maxStart < searchStart) continue;
      final phrase = tokens.sublist(tokens.length - phraseLen);
      for (var i = searchStart; i <= maxStart; i++) {
        var mismatches = 0;
        final allowedMismatches = phraseLen >= 6 ? 2 : 1;
        for (var j = 0; j < phraseLen; j++) {
          if (realWords[i + j].normalized != phrase[j]) {
            mismatches++;
            if (mismatches > allowedMismatches) break;
          }
        }
        if (mismatches <= allowedMismatches &&
            _hasReliableFuzzyPhraseEvidence(realWords, i, phraseLen)) {
          return realWords[i + phraseLen - 1].index;
        }
      }
    }
    return null;
  }

  int? approximateTarget({
    required List<ScriptWord> words,
    required String transcript,
    required int currentIndex,
    required int? visibleWordStart,
    required int? visibleWordEnd,
    double minimumScore = 0.88,
  }) {
    if (visibleWordStart == null || visibleWordEnd == null) return null;
    if (transcript.trim().isEmpty || words.isEmpty) return null;
    final queryTokens = ApproximateSpokenSearchService.tokenize(transcript);
    if (queryTokens.length < 4) return null;

    final start =
        visibleWordStart <= visibleWordEnd ? visibleWordStart : visibleWordEnd;
    final end =
        visibleWordStart <= visibleWordEnd ? visibleWordEnd : visibleWordStart;
    final safeStart = start.clamp(0, words.length - 1).toInt();
    final safeEnd = end.clamp(safeStart, words.length - 1).toInt();
    final candidateWords = words
        .where((word) =>
            !word.isNewline &&
            word.normalized.isNotEmpty &&
            word.index > currentIndex &&
            word.index >= safeStart &&
            word.index <= safeEnd)
        .toList(growable: false);
    if (candidateWords.length < 4) return null;
    final maxAdvance = _maxApproximateAdvance(queryTokens.length);

    final matches = const ApproximateSpokenSearchService().findRanked(
      words: candidateWords,
      spokenText: transcript,
      minimumScore: minimumScore,
      limit: 12,
    );
    final safeMatches = matches
        .where((match) =>
            match.endWordIndex > currentIndex &&
            match.endWordIndex - currentIndex <= maxAdvance)
        .toList(growable: false);
    if (safeMatches.isEmpty) return null;
    safeMatches.sort(
      (a, b) => a.startWordIndex.compareTo(b.startWordIndex),
    );
    return safeMatches.first.endWordIndex;
  }

  int? anchorTarget({
    required List<ScriptWord> words,
    required String transcript,
    required int currentIndex,
    required int? visibleWordStart,
    required int? visibleWordEnd,
    double minimumAnchorSimilarity = 0.78,
    int maxLeadingNoiseTokens = 2,
    int maxSkippedTokens = 2,
    int maxSkippedScriptWords = 1,
  }) {
    if (visibleWordStart == null || visibleWordEnd == null) return null;
    final queryTokens = ApproximateSpokenSearchService.tokenize(transcript);
    if (queryTokens.length < 3 || words.isEmpty) return null;

    final start =
        visibleWordStart <= visibleWordEnd ? visibleWordStart : visibleWordEnd;
    final end =
        visibleWordStart <= visibleWordEnd ? visibleWordEnd : visibleWordStart;
    final safeStart = start.clamp(0, words.length - 1).toInt();
    final safeEnd = end.clamp(safeStart, words.length - 1).toInt();
    final candidateWords = words
        .where((word) =>
            !word.isNewline &&
            word.normalized.isNotEmpty &&
            word.index > currentIndex &&
            word.index >= safeStart &&
            word.index <= safeEnd)
        .toList(growable: false);
    if (candidateWords.length < 3) return null;

    _AnchorRun? best;
    for (var i = 0; i < candidateWords.length; i++) {
      var tokenIndex = 0;
      var matched = 0;
      var score = 0.0;
      var skippedTokens = 0;
      var skippedScriptWords = 0;
      var endWord = candidateWords[i].index;
      for (var j = i;
          j < candidateWords.length && tokenIndex < queryTokens.length;
          j++) {
        final word = candidateWords[j];
        var bestToken = -1;
        var bestSim = 0.0;
        final tokenLimit = (tokenIndex + 3).clamp(
          tokenIndex + 1,
          queryTokens.length,
        );
        for (var t = tokenIndex; t < tokenLimit; t++) {
          final sim = WordAligner.spokenWordSimilarity(queryTokens[t], word);
          if (sim > bestSim) {
            bestSim = sim;
            bestToken = t;
          }
        }
        if (bestSim < minimumAnchorSimilarity || bestToken < 0) {
          if (matched == 0) continue;
          skippedScriptWords++;
          if (skippedScriptWords > maxSkippedScriptWords) break;
          if (j - i > queryTokens.length + 2) break;
          continue;
        }
        final skippedBeforeMatch = bestToken - tokenIndex;
        final leadingNoiseIsSafe = matched > 0 ||
            _leadingNoiseIsFiller(
              queryTokens,
              tokenIndex,
              skippedBeforeMatch,
            );
        if (matched == 0 && bestToken > maxLeadingNoiseTokens) {
          break;
        }
        if (!leadingNoiseIsSafe) {
          break;
        }
        if (matched > 0 && skippedBeforeMatch > 0) {
          skippedTokens += skippedBeforeMatch;
          if (skippedTokens > maxSkippedTokens) break;
        }
        matched++;
        score += bestSim;
        tokenIndex = bestToken + 1;
        endWord = word.index;
        if (matched >= 2 && score / matched >= minimumAnchorSimilarity) {
          final run = _AnchorRun(
            endWord,
            matched,
            score / matched,
            skippedTokens,
            skippedScriptWords,
          );
          if (best == null || run.isBetterThan(best)) best = run;
        }
      }
    }
    if (best == null) return null;
    final hasTightEvidence =
        best.skippedTokens == 0 && best.skippedScriptWords <= 1;
    final hasEnoughEvidence = best.matchedAnchors >= 4 ||
        (best.matchedAnchors >= 3 &&
            (hasTightEvidence || best.averageSimilarity >= 0.90)) ||
        (best.matchedAnchors >= 2 &&
            hasTightEvidence &&
            best.averageSimilarity >= 0.82);
    return hasEnoughEvidence ? best.targetIndex : null;
  }

  static bool _leadingNoiseIsFiller(
    List<String> queryTokens,
    int start,
    int count,
  ) {
    if (count <= 0) return true;
    if (start < 0 || start + count > queryTokens.length) return false;
    for (var i = start; i < start + count; i++) {
      if (!_isFillerToken(queryTokens[i])) return false;
    }
    return true;
  }

  static bool _isFillerToken(String token) {
    switch (token) {
      case 'um':
      case 'uh':
      case 'ah':
      case 'er':
      case 'erm':
      case 'mm':
      case 'hmm':
      case 'like':
      case 'so':
      case 'well':
      case 'ok':
      case 'okay':
      case 'now':
      case 'then':
      case 'אמ':
      case 'אממ':
      case 'אה':
      case 'אז':
      case 'טוב':
      case 'כאילו':
        return true;
      default:
        return false;
    }
  }

  static bool _hasReliableFuzzyPhraseEvidence(
    List<ScriptWord> realWords,
    int start,
    int phraseLen,
  ) {
    var meaningfulWords = 0;
    var hasDistinctiveWord = false;

    for (var i = start; i < start + phraseLen; i++) {
      final token = realWords[i].normalized.normalizeForMatching();
      if (token.isEmpty || _isFuzzyStopWord(token)) continue;

      final isRtl = realWords[i].isRtl;
      final meaningfulLength = isRtl ? 3 : 4;
      final distinctiveLength = isRtl ? 4 : 5;
      if (token.length >= meaningfulLength) meaningfulWords++;
      if (token.length >= distinctiveLength) hasDistinctiveWord = true;
    }

    return hasDistinctiveWord || meaningfulWords >= 3;
  }

  static bool _isFuzzyStopWord(String token) {
    switch (token) {
      case 'a':
      case 'an':
      case 'the':
      case 'of':
      case 'to':
      case 'in':
      case 'on':
      case 'at':
      case 'by':
      case 'for':
      case 'from':
      case 'with':
      case 'and':
      case 'or':
      case 'is':
      case 'are':
      case 'was':
      case 'were':
      case 'be':
      case 'it':
      case 'this':
      case 'that':
      case 'these':
      case 'those':
      case 'one':
      case 'i':
      case 'we':
      case 'you':
      case 'he':
      case 'she':
      case 'they':
      case 'me':
      case 'my':
      case 'your':
      case 'our':
      case 'their':
      case 'not':
      case 'go':
      case 'going':
      case 'do':
      case 'does':
      case 'did':
      case 'so':
      case 'now':
      case 'then':
      case 'ה':
      case 'של':
      case 'את':
      case 'עם':
      case 'על':
      case 'אל':
      case 'או':
      case 'אם':
      case 'זה':
      case 'זו':
      case 'אני':
      case 'אתה':
      case 'אתם':
      case 'אנחנו':
        return true;
      default:
        return false;
    }
  }

  static int _maxApproximateAdvance(int tokenCount) {
    if (tokenCount >= 8) return 96;
    if (tokenCount >= 6) return 64;
    return 32;
  }

  int? globalApproximateTarget({
    required List<ScriptWord> words,
    required String transcript,
    required int currentIndex,
    double minimumScore = 0.84,
  }) {
    final queryTokens = ApproximateSpokenSearchService.tokenize(transcript);
    if (queryTokens.length < 7 || words.isEmpty) return null;

    final candidateWords = words
        .where((word) =>
            !word.isNewline &&
            word.index > currentIndex &&
            word.normalized.isNotEmpty)
        .toList(growable: false);
    if (candidateWords.length < 7) return null;

    final match = const ApproximateSpokenSearchService().findBest(
      words: candidateWords,
      spokenText: transcript,
      minimumScore: minimumScore,
    );
    if (match == null || match.endWordIndex <= currentIndex) return null;
    return match.endWordIndex;
  }
}

class _AnchorRun {
  final int targetIndex;
  final int matchedAnchors;
  final double averageSimilarity;
  final int skippedTokens;
  final int skippedScriptWords;

  const _AnchorRun(
    this.targetIndex,
    this.matchedAnchors,
    this.averageSimilarity,
    this.skippedTokens,
    this.skippedScriptWords,
  );

  bool isBetterThan(_AnchorRun? other) {
    if (other == null) return true;
    if (matchedAnchors != other.matchedAnchors) {
      return matchedAnchors > other.matchedAnchors;
    }
    if ((averageSimilarity - other.averageSimilarity).abs() > 0.04) {
      return averageSimilarity > other.averageSimilarity;
    }
    if (skippedScriptWords != other.skippedScriptWords) {
      return skippedScriptWords < other.skippedScriptWords;
    }
    if (skippedTokens != other.skippedTokens) {
      return skippedTokens < other.skippedTokens;
    }
    return targetIndex < other.targetIndex;
  }
}
