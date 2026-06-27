part of 'word_aligner.dart';

class _SentenceRecoveryCandidate {
  final int start;
  final int end;
  final int matched;
  final int span;
  final double ratio;
  final double confidence;

  const _SentenceRecoveryCandidate({
    required this.start,
    required this.end,
    required this.matched,
    required this.span,
    required this.ratio,
    required this.confidence,
  });

  bool isBetterThan(_SentenceRecoveryCandidate? other, int searchStart) {
    if (other == null) return true;
    if ((confidence - other.confidence).abs() > 0.04) {
      return confidence > other.confidence;
    }
    if (matched != other.matched) return matched > other.matched;
    return (start - searchStart).abs() < (other.start - searchStart).abs();
  }
}

AlignmentResult? _sentenceRecoveryMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int visibleEnd,
  required bool policyBulletMode,
  required SttEvidenceThreshold recoveryThreshold,
  double recoveryRatio = 0.75,
}) {
  if (policyBulletMode) return null;
  final minRecoveryWords = recoveryThreshold.smallWords.clamp(3, 6).toInt();
  if (transcriptWords.length < minRecoveryWords) return null;
  final spanEnd = visibleEnd.clamp(searchStart, script.length - 1).toInt();
  if (spanEnd < searchStart) return null;
  final maxCandidateSpan =
      (transcriptWords.length + 2).clamp(minRecoveryWords, 18).toInt();
  _SentenceRecoveryCandidate? best;

  for (var candidateStart = searchStart;
      candidateStart <= spanEnd;
      candidateStart++) {
    final first = script[candidateStart];
    if (first.isNewline || _isUnspeakable(first) || first.isOptionalCue) {
      continue;
    }

    var spokenPtr = 0;
    var matched = 0;
    var lastMatch = -1;
    var speakableSpan = 0;
    var score = 0.0;
    final matchedWords = <String>[];

    for (var i = candidateStart; i <= spanEnd; i++) {
      final word = script[i];
      if (word.isNewline || _isUnspeakable(word) || word.isOptionalCue) {
        continue;
      }
      speakableSpan++;
      if (speakableSpan > maxCandidateSpan) break;

      final target = word.normalized;
      if (target.isEmpty) continue;
      final threshold = word.isRtl
          ? WordAligner._hebrewMatchThreshold
          : WordAligner._matchThreshold;
      for (var j = spokenPtr; j < transcriptWords.length; j++) {
        var bestSim = _wordSimilarity(transcriptWords[j], target, word.isRtl);
        var bestN = 1;
        for (var n = 2; n <= 3 && j + n <= transcriptWords.length; n++) {
          final joined = transcriptWords.sublist(j, j + n).join();
          final sim = _wordSimilarity(joined, target, word.isRtl);
          if (sim > bestSim) {
            bestSim = sim;
            bestN = n;
          }
        }
        if (bestSim >= threshold) {
          matched++;
          lastMatch = i;
          score += bestSim;
          matchedWords.add(target);
          spokenPtr = j + bestN;
          break;
        }
      }
      if (spokenPtr >= transcriptWords.length) break;
    }

    if (lastMatch < candidateStart || matched < minRecoveryWords) continue;
    if (!recoveryThreshold.passes(matchedWords)) continue;
    final ratio = speakableSpan > 0 ? matched / speakableSpan : 0.0;
    if (ratio < recoveryRatio) continue;
    final average = score / matched;
    final distancePenalty = (candidateStart - searchStart) * 0.012;
    final confidence = (ratio * 0.7 + average * 0.3 - distancePenalty)
        .clamp(0.0, 1.0)
        .toDouble();
    final candidate = _SentenceRecoveryCandidate(
      start: candidateStart,
      end: lastMatch,
      matched: matched,
      span: speakableSpan,
      ratio: ratio,
      confidence: confidence,
    );
    if (candidate.isBetterThan(best, searchStart)) best = candidate;
  }

  if (best == null) return null;
  return AlignmentResult(
    best.end,
    best.confidence,
    'SENTENCE_RECOVERY@${best.start}: matched=${best.matched}/${best.span} '
    'ratio=${best.ratio.toStringAsFixed(2)} end=${best.end}',
    SttAlignmentDecision.advance,
    SttAlignmentKind.sentenceRecovery,
    SttThresholdFamily.visibleSkip,
    [for (var i = best.start; i <= best.end; i++) i],
    transcriptWords.length > best.matched
        ? transcriptWords.sublist(transcriptWords.length - best.matched)
        : transcriptWords,
    best.start,
    best.end,
  );
}
