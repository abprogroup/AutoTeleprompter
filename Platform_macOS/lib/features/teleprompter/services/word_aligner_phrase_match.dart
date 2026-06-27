part of 'word_aligner.dart';

AlignmentResult? _nearbyPhrasePriorityMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int windowEnd,
  required int lastConfirmedIndex,
  int maxPhraseWords = WordAligner._nearPhraseMaxWords,
  int? maxJump,
  int minPhraseWords = 3,
  SttEvidenceThreshold? evidenceThreshold,
  SttEvidenceThreshold? scriptGapThreshold,
  SttThresholdFamily thresholdFamily = SttThresholdFamily.none,
  bool scanFullWindow = false,
  bool scanAllTranscriptPhrases = false,
  double? overrideWordThreshold,
  double minPhraseScore = WordAligner._matchThreshold,
  String debugPrefix = 'NEAR_PHRASE_PRIORITY',
}) {
  if (transcriptWords.length < minPhraseWords) return null;

  final phraseWindowEnd = scanFullWindow
      ? windowEnd
      : (searchStart + WordAligner._nearPhrasePriorityWindow)
          .clamp(searchStart, windowEnd)
          .toInt();
  if (phraseWindowEnd <= searchStart) return null;

  final longestPhrase = transcriptWords.length < maxPhraseWords
      ? transcriptWords.length
      : maxPhraseWords;

  for (int phraseLen = longestPhrase;
      phraseLen >= minPhraseWords;
      phraseLen--) {
    final phraseStarts = scanAllTranscriptPhrases
        ? [for (var i = transcriptWords.length - phraseLen; i >= 0; i--) i]
        : [transcriptWords.length - phraseLen];

    double phraseBestScore = 0.0;
    int phraseBestStart = -1;
    int phraseBestEnd = -1;
    int phraseBestTranscriptStart = -1;
    double phraseBestGapCost = 0.0;

    for (final transcriptStart in phraseStarts) {
      final spokenPhrase = transcriptWords.sublist(
        transcriptStart,
        transcriptStart + phraseLen,
      );
      if (evidenceThreshold != null) {
        if (!evidenceThreshold.passes(spokenPhrase)) continue;
      } else if (!_hasUsefulPhraseWords(spokenPhrase, minPhraseWords)) {
        continue;
      }

      double bestScore = 0.0;
      int bestStart = -1;
      int bestEnd = -1;
      double bestGapCost = 0.0;

      for (int i = searchStart; i < phraseWindowEnd; i++) {
        if (script[i].isNewline || _isUnspeakable(script[i])) continue;

        int si = i;
        int matched = 0;
        double score = 0.0;
        double gapCost = 0.0;
        int endIdx = i;

        for (int j = 0; j < spokenPhrase.length && si < phraseWindowEnd; si++) {
          if (script[si].isNewline || _isUnspeakable(script[si])) {
            continue;
          }

          final scriptWord = script[si].normalized;
          final sim =
              _wordSimilarity(spokenPhrase[j], scriptWord, script[si].isRtl);
          final threshold = overrideWordThreshold ??
              (script[si].isRtl
                  ? WordAligner._hebrewMatchThreshold
                  : WordAligner._matchThreshold);
          if (sim < threshold) {
            if (script[si].isOptionalCue) continue;
            if (matched == 0 || scriptGapThreshold == null) break;
            final nextGapCost =
                gapCost + scriptGapThreshold.evidenceCost(scriptWord);
            if (nextGapCost > scriptGapThreshold.smallWords) break;
            gapCost = nextGapCost;
            continue;
          }

          matched++;
          score += sim;
          endIdx = si;
          j++;
        }

        if (matched != spokenPhrase.length) continue;

        final distance = i - searchStart;
        final adjustedScore =
            (score / spokenPhrase.length) - (distance * 0.018);
        final clearlyBetter = adjustedScore > bestScore + 0.06;
        final nearTieButCloser = (adjustedScore - bestScore).abs() <= 0.06 &&
            (bestStart < 0 || i < bestStart);
        if (clearlyBetter || nearTieButCloser) {
          bestScore = adjustedScore;
          bestStart = i;
          bestEnd = endIdx;
          bestGapCost = gapCost;
        }
      }

      if (bestStart >= 0 &&
          bestEnd > lastConfirmedIndex &&
          bestScore >= minPhraseScore &&
          (maxJump == null || bestEnd - lastConfirmedIndex <= maxJump) &&
          (bestScore > phraseBestScore ||
              (bestScore == phraseBestScore &&
                  transcriptStart > phraseBestTranscriptStart))) {
        phraseBestScore = bestScore;
        phraseBestStart = bestStart;
        phraseBestEnd = bestEnd;
        phraseBestTranscriptStart = transcriptStart;
        phraseBestGapCost = bestGapCost;
      }
    }

    if (phraseBestStart >= 0) {
      return AlignmentResult(
        phraseBestEnd,
        phraseBestScore,
        '$debugPrefix@$phraseBestStart: words=$phraseLen transcript=$phraseBestTranscriptStart end=$phraseBestEnd score=${phraseBestScore.toStringAsFixed(2)} gapCost=${phraseBestGapCost.toStringAsFixed(1)}',
        SttAlignmentDecision.advance,
        debugPrefix == 'NEAR_PHRASE_PRIORITY'
            ? SttAlignmentKind.visiblePhrase
            : SttAlignmentKind.localRecoveryPhrase,
        thresholdFamily,
        [for (var i = phraseBestStart; i <= phraseBestEnd; i++) i],
        transcriptWords
            .sublist(phraseBestTranscriptStart,
                phraseBestTranscriptStart + phraseLen)
            .toList(growable: false),
        phraseBestStart,
        phraseBestEnd,
      );
    }
  }

  return null;
}

AlignmentResult? _contiguousNextPhraseMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int lastConfirmedIndex,
  required int maxPhraseWords,
  required SttEvidenceThreshold evidenceThreshold,
  required SttThresholdFamily thresholdFamily,
  double? overrideWordThreshold,
  double minPhraseScore = WordAligner._matchThreshold,
}) {
  if (transcriptWords.length < 2 || searchStart >= script.length) return null;

  final longest =
      [maxPhraseWords, transcriptWords.length].reduce((a, b) => a < b ? a : b);

  for (var phraseLen = longest; phraseLen >= 2; phraseLen--) {
    final spokenPhrase =
        transcriptWords.sublist(transcriptWords.length - phraseLen);
    if (!evidenceThreshold.passes(spokenPhrase)) continue;

    var score = 0.0;
    var matched = true;
    var spokenIndex = 0;
    var target = lastConfirmedIndex;
    for (var si = searchStart;
        si < script.length && spokenIndex < phraseLen;
        si++) {
      final scriptWord = script[si];
      if (scriptWord.isNewline || _isUnspeakable(scriptWord)) continue;
      final threshold = overrideWordThreshold ??
          (scriptWord.isRtl
              ? WordAligner._hebrewMatchThreshold
              : WordAligner._matchThreshold);
      final sim = _wordSimilarity(
        spokenPhrase[spokenIndex],
        scriptWord.normalized,
        scriptWord.isRtl,
      );
      if (sim < threshold) {
        if (scriptWord.isOptionalCue) continue;
        matched = false;
        break;
      }
      score += sim;
      target = scriptWord.index;
      spokenIndex++;
    }
    if (!matched || spokenIndex != phraseLen) continue;

    final average = score / phraseLen;
    if (average >= minPhraseScore && target > lastConfirmedIndex) {
      return AlignmentResult(
        target,
        average,
        'NEXT_PHRASE: words=$phraseLen end=$target score=${average.toStringAsFixed(2)}',
        SttAlignmentDecision.advance,
        SttAlignmentKind.nextPhrase,
        thresholdFamily,
        const [],
        spokenPhrase,
        searchStart,
        target,
      );
    }
  }

  return null;
}
