part of 'word_aligner.dart';

class _NameAnchorRun {
  final int start;
  final int end;
  final int transcriptStart;
  final int words;
  final double score;

  const _NameAnchorRun({
    required this.start,
    required this.end,
    required this.transcriptStart,
    required this.words,
    required this.score,
  });

  bool isBetterThan(_NameAnchorRun? other, int searchStart) {
    if (other == null) return true;
    if ((score - other.score).abs() > 0.04) return score > other.score;
    if (words != other.words) return words > other.words;
    return (start - searchStart).abs() < (other.start - searchStart).abs();
  }
}

// Deferred V6 research path. Do not wire this into live STT advancement until
// proper-name matching has script-side pronunciation/vocabulary controls.
// ignore: unused_element
AlignmentResult? _properNameAnchorMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int windowEnd,
  required int lastConfirmedIndex,
  required int maxJump,
}) {
  if (transcriptWords.length < 2 || windowEnd <= searchStart) return null;
  final recent = transcriptWords.length > 12
      ? transcriptWords.sublist(transcriptWords.length - 12)
      : transcriptWords;
  _NameAnchorRun? best;

  for (var i = searchStart; i < windowEnd; i++) {
    if (!_isLikelyProperNameWord(script[i])) continue;
    final nameWords = <ScriptWord>[];
    for (var si = i; si < windowEnd && nameWords.length < 4; si++) {
      final word = script[si];
      if (word.isNewline || _isUnspeakable(word)) break;
      if (!_isLikelyProperNameWord(word)) break;
      nameWords.add(word);
    }
    if (nameWords.length < 2) continue;

    for (var len = nameWords.length; len >= 2; len--) {
      for (var transcriptStart = recent.length - len;
          transcriptStart >= 0;
          transcriptStart--) {
        var score = 0.0;
        var weakest = 1.0;
        for (var j = 0; j < len; j++) {
          final word = nameWords[j];
          final sim = _wordSimilarity(
            recent[transcriptStart + j],
            word.normalized,
            word.isRtl,
          );
          if (sim < weakest) weakest = sim;
          score += sim;
        }
        final average = score / len;
        final target = nameWords[len - 1].index;
        final jump = target - lastConfirmedIndex;
        if (jump <= 0 || jump > maxJump) continue;
        if (weakest < 0.68 || average < 0.82) continue;
        final adjusted = average - ((i - searchStart) * 0.012);
        final run = _NameAnchorRun(
          start: i,
          end: target,
          transcriptStart: transcriptStart,
          words: len,
          score: adjusted.clamp(0.0, 1.0),
        );
        if (run.isBetterThan(best, searchStart)) best = run;
      }
    }
  }

  if (best == null) return null;
  final percent = (best.score * 100).round();
  return AlignmentResult(
    best.end,
    best.score,
    'NAME_ANCHOR@${best.start}: words=${best.words} '
    'transcript=${best.transcriptStart} end=${best.end} score=$percent%',
  );
}

bool _isLikelyProperNameWord(ScriptWord word) {
  if (word.isNewline || word.normalized.length < 2) return false;
  if (_isNameAnchorStopWord(word.normalized)) return false;
  final cleaned = word.raw
      .replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), ' ')
      .replaceAll(RegExp(r"[^A-Za-z'\- ]"), ' ')
      .trim();
  if (cleaned.length < 2) return false;
  final firstAlpha = RegExp(r'[A-Za-z]').firstMatch(cleaned);
  if (firstAlpha == null) return false;
  final ch = firstAlpha.group(0)!;
  if (ch != ch.toUpperCase()) return false;
  return RegExp(r'[a-z]').hasMatch(cleaned);
}

bool _isNameAnchorStopWord(String normalized) {
  const stopWords = {
    'mr',
    'mrs',
    'ms',
    'dr',
    'prof',
    'mayor',
    'chairman',
    'minister',
    'president',
    'federation',
    'authorities',
    'authority',
    'local',
    'session',
    'plenary',
    'partners',
    'leadership',
  };
  return stopWords.contains(normalized.replaceAll("'", ''));
}
