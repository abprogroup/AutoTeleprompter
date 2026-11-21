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
  bool allowOneSpokenSubstitution = false,
  double? overrideWordThreshold,
  double minPhraseScore = WordAligner._matchThreshold,
  String debugPrefix = 'NEAR_PHRASE_PRIORITY',
}) {
  if (transcriptWords.length < minPhraseWords) return null;

  // Preserve the established tail-first behavior. Search earlier phrases only
  // when the tail is noise/an unfinished word, not when it already matches.
  if (scanAllTranscriptPhrases) {
    final tail = _nearbyPhrasePriorityMatch(
      script: script,
      transcriptWords: transcriptWords,
      searchStart: searchStart,
      windowEnd: windowEnd,
      lastConfirmedIndex: lastConfirmedIndex,
      maxPhraseWords: maxPhraseWords,
      maxJump: maxJump,
      minPhraseWords: minPhraseWords,
      evidenceThreshold: evidenceThreshold,
      scriptGapThreshold: scriptGapThreshold,
      thresholdFamily: thresholdFamily,
      scanFullWindow: scanFullWindow,
      allowOneSpokenSubstitution: allowOneSpokenSubstitution,
      overrideWordThreshold: overrideWordThreshold,
      minPhraseScore: minPhraseScore,
      debugPrefix: debugPrefix,
    );
    if (tail != null) return tail;
  }

  final phraseWindowEnd =
      scanFullWindow
          ? windowEnd
          : (searchStart + WordAligner._nearPhrasePriorityWindow)
              .clamp(searchStart, windowEnd)
              .toInt();
  if (phraseWindowEnd <= searchStart) return null;

  final longestPhrase =
      transcriptWords.length < maxPhraseWords
          ? transcriptWords.length
          : maxPhraseWords;

  for (
    int phraseLen = longestPhrase;
    phraseLen >= minPhraseWords;
    phraseLen--
  ) {
    final phraseStarts =
        scanAllTranscriptPhrases
            ? [for (var i = transcriptWords.length - phraseLen; i >= 0; i--) i]
            : [transcriptWords.length - phraseLen];

    double phraseBestScore = 0.0;
    int phraseBestStart = -1;
    int phraseBestEnd = -1;
    int phraseBestTranscriptStart = -1;
    double phraseBestGapCost = 0.0;
    List<String> phraseBestEvidence = const [];

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
      List<String> bestEvidence = const [];
      final allowOneSpokenSub =
          allowOneSpokenSubstitution &&
          thresholdFamily == SttThresholdFamily.visibleSkip &&
          scriptGapThreshold != null &&
          spokenPhrase.length >= 4;

      for (int i = searchStart; i < phraseWindowEnd; i++) {
        if (script[i].isNewline || _isUnspeakable(script[i])) continue;

        int si = i;
        int matched = 0;
        int substitutions = 0;
        double score = 0.0;
        double gapCost = 0.0;
        int endIdx = i;
        final matchedSpoken = <String>[];

        for (int j = 0; j < spokenPhrase.length && si < phraseWindowEnd; si++) {
          if (script[si].isNewline || _isUnspeakable(script[si])) {
            continue;
          }

          final scriptWord = script[si].normalized;
          final sim = _wordSimilarity(
            spokenPhrase[j],
            scriptWord,
            script[si].isRtl,
          );
          final threshold =
              overrideWordThreshold ??
              (script[si].isRtl
                  ? WordAligner._hebrewMatchThreshold
                  : WordAligner._matchThreshold);
          if (sim < threshold) {
            if (script[si].isOptionalCue) continue;
            // Allow at most one interior spoken substitution (e.g. a single
            // STT mishearing like "פסטיבל" for "וציוונו") when the very next
            // spoken word matches the next speakable script word. The
            // substituted word contributes 0.0 evidence.
            if (allowOneSpokenSub &&
                substitutions == 0 &&
                matched >= 1 &&
                j + 1 < spokenPhrase.length &&
                !RegExp(r'\d').hasMatch(spokenPhrase[j]) &&
                !RegExp(r'\d').hasMatch(scriptWord)) {
              final nextSi = WordAligner.nextRequiredSpeakableIndex(
                script,
                si + 1,
              );
              if (nextSi < phraseWindowEnd) {
                final nextWord = script[nextSi];
                final nextThreshold =
                    overrideWordThreshold ??
                    (nextWord.isRtl
                        ? WordAligner._hebrewMatchThreshold
                        : WordAligner._matchThreshold);
                final nextSim = _wordSimilarity(
                  spokenPhrase[j + 1],
                  nextWord.normalized,
                  nextWord.isRtl,
                );
                if (nextSim >= nextThreshold) {
                  substitutions++;
                  j++;
                  continue;
                }
              }
            }
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
          matchedSpoken.add(spokenPhrase[j]);
          j++;
        }

        if (matched + substitutions != spokenPhrase.length) continue;
        if (substitutions > 0 &&
            evidenceThreshold != null &&
            !evidenceThreshold.passes(matchedSpoken)) {
          continue;
        }

        final distance = i - searchStart;
        final adjustedScore =
            (score / spokenPhrase.length) - (distance * 0.018);
        final clearlyBetter = adjustedScore > bestScore + 0.06;
        final nearTieButCloser =
            (adjustedScore - bestScore).abs() <= 0.06 &&
            (bestStart < 0 || i < bestStart);
        if (clearlyBetter || nearTieButCloser) {
          bestScore = adjustedScore;
          bestStart = i;
          bestEnd = endIdx;
          bestGapCost = gapCost;
          bestEvidence = List<String>.unmodifiable(matchedSpoken);
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
        phraseBestEvidence = bestEvidence;
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
        phraseBestEvidence,
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

  final longest = [
    maxPhraseWords,
    transcriptWords.length,
  ].reduce((a, b) => a < b ? a : b);

  for (var phraseLen = longest; phraseLen >= 2; phraseLen--) {
    final spokenPhrase = transcriptWords.sublist(
      transcriptWords.length - phraseLen,
    );
    if (!evidenceThreshold.passes(spokenPhrase)) continue;

    var score = 0.0;
    var matched = true;
    var spokenIndex = 0;
    var target = lastConfirmedIndex;
    for (
      var si = searchStart;
      si < script.length && spokenIndex < phraseLen;
      si++
    ) {
      final scriptWord = script[si];
      if (scriptWord.isNewline || _isUnspeakable(scriptWord)) continue;
      final threshold =
          overrideWordThreshold ??
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

/// Evaluates visible-skip phrase matching directly on the visible window
/// without letting a weak local next-word similarity shadow it.
AlignmentResult? visibleSkipPreviewMatch({
  required List<ScriptWord> script,
  required String transcript,
  required int lastConfirmedIndex,
  required int? visibleSkipStartIndex,
  required int maxSkipTargetIndex,
  required SttRecognitionPolicy policy,
  required bool strictBulletMode,
}) {
  if (script.isEmpty || transcript.trim().isEmpty) return null;
  final policyBulletMode = policy.bulletMode || strictBulletMode;
  final numberScanStart =
      (lastConfirmedIndex + 1).clamp(0, script.length).toInt();
  final numberScanEnd =
      (maxSkipTargetIndex + 1).clamp(numberScanStart, script.length).toInt();
  final relaxedPolicy = SttRecognitionPolicy(
    bulletMode: policy.bulletMode,
    visibleSkipEnabled: true,
    hardVisibleSkipEnabled: false,
    startAdvance: policy.startAdvance,
    safetyRecovery: policy.safetyRecovery,
    bulletAdvance: policy.bulletAdvance,
    visibleSkip: SttEvidenceThreshold(
      2,
      1,
      policy.visibleSkip.bigWordMinLetters,
    ),
  );
  final numberOutcome = _numberAwareMatch(
    script: script,
    transcript: transcript,
    lastConfirmedIndex: lastConfirmedIndex,
    scanStart: numberScanStart,
    scanEnd: numberScanEnd,
    strictBulletMode: policyBulletMode,
    policy: relaxedPolicy,
    visibleSkipEnabled: true,
    visibleSkipStartIndex: visibleSkipStartIndex,
  );
  if (numberOutcome?.result != null) {
    final res = numberOutcome!.result!;
    return (res.thresholdFamily == SttThresholdFamily.visibleSkip ||
            res.kind == SttAlignmentKind.visiblePhrase ||
            res.kind == SttAlignmentKind.sentenceRecovery)
        ? res
        : null;
  }
  if (numberOutcome?.blocksGenericFallback ?? false) return null;

  final rawWords =
      transcript
          .split(RegExp(r'\s+'))
          .map((w) => w.trim().normalizeForMatching())
          .where((w) => w.isNotEmpty)
          .toList();
  final transcriptWords = _collapseAbbreviations(rawWords);
  if (transcriptWords.isEmpty) return null;
  final searchStart = WordAligner.nextSpeakableIndex(
    script,
    lastConfirmedIndex + 1,
  );
  if (searchStart >= script.length) return null;
  final windowEnd =
      (maxSkipTargetIndex + 1).clamp(searchStart + 1, script.length).toInt();
  final visibleScanStart =
      (visibleSkipStartIndex ?? searchStart).clamp(searchStart, windowEnd).toInt();
  return _nearbyPhrasePriorityMatch(
    script: script,
    transcriptWords: transcriptWords,
    searchStart: visibleScanStart,
    windowEnd: windowEnd,
    lastConfirmedIndex: lastConfirmedIndex,
    scanFullWindow: true,
    scanAllTranscriptPhrases: true,
    minPhraseWords: relaxedPolicy.visibleSkip.bigWords,
    evidenceThreshold: relaxedPolicy.visibleSkip,
    scriptGapThreshold: policy.safetyRecovery,
    thresholdFamily: SttThresholdFamily.visibleSkip,
    overrideWordThreshold:
        policyBulletMode ? WordAligner._strictPhraseThreshold : null,
    minPhraseScore:
        policyBulletMode
            ? WordAligner._strictPhraseThreshold
            : WordAligner._matchThreshold,
    debugPrefix: 'NEAR_PHRASE_PRIORITY',
  );
}

AlignmentResult? _visibleSkipOneSubFallback({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int visibleScanStart,
  required int windowEnd,
  required int lastConfirmedIndex,
  required SttRecognitionPolicy effectivePolicy,
  required bool policyBulletMode,
}) => _nearbyPhrasePriorityMatch(
  script: script,
  transcriptWords: transcriptWords,
  searchStart: visibleScanStart,
  windowEnd: windowEnd,
  lastConfirmedIndex: lastConfirmedIndex,
  scanFullWindow: true,
  scanAllTranscriptPhrases: true,
  allowOneSpokenSubstitution: true,
  minPhraseWords: effectivePolicy.visibleSkip.bigWords,
  evidenceThreshold: effectivePolicy.visibleSkip,
  scriptGapThreshold: effectivePolicy.safetyRecovery,
  thresholdFamily: SttThresholdFamily.visibleSkip,
  overrideWordThreshold:
      policyBulletMode ? WordAligner._strictPhraseThreshold : null,
  minPhraseScore:
      policyBulletMode
          ? WordAligner._strictPhraseThreshold
          : WordAligner._matchThreshold,
  debugPrefix: 'NEAR_PHRASE_PRIORITY',
);
