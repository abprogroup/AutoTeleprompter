import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';
import 'approximate_spoken_search_service.dart';

class SttVisibleRelockService {
  const SttVisibleRelockService();

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
        if (mismatches <= allowedMismatches) {
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

    final start =
        visibleWordStart <= visibleWordEnd ? visibleWordStart : visibleWordEnd;
    final end =
        visibleWordStart <= visibleWordEnd ? visibleWordEnd : visibleWordStart;
    final safeStart = start.clamp(0, words.length - 1).toInt();
    final safeEnd = end.clamp(safeStart, words.length - 1).toInt();
    final candidateWords = words
        .where((word) =>
            !word.isNewline &&
            word.index > currentIndex &&
            word.index >= safeStart &&
            word.index <= safeEnd)
        .toList(growable: false);
    if (candidateWords.length < 4) return null;

    final match = const ApproximateSpokenSearchService().findBest(
      words: candidateWords,
      spokenText: transcript,
      minimumScore: minimumScore,
    );
    if (match == null || match.endWordIndex <= currentIndex) return null;
    return match.endWordIndex;
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
