import 'package:flutter/material.dart';
import '../../script/models/script_word.dart';
import '../../../core/extensions/string_extensions.dart';

part 'word_aligner_tokenizer.dart';
part 'word_aligner_similarity.dart';
part 'word_aligner_policy.dart';
part 'word_aligner_name_anchor.dart';

class WordAligner {
  // -- Tuning constants -------------------------------------------------------
  // Window size to search ahead (in non-newline words).
  static const int _searchWindowSize = 50;
  // Max words for a SINGLE-word match (prevents false jumps on common words).
  // Looser on mobile: Apple iOS STT often returns multi-word chunks and splits
  // compound words (e.g. "AutoTeleprompter" -> "auto teleprompter").
  static const int _maxSingleJump = 5;
  // Nearby phrase window checked before the visible-skip fallback.
  static const int _nearPhrasePriorityWindow = 50;
  static const int _nearPhraseMaxWords = 8;
  static const int _localRecoveryPhraseMaxWords = 5;
  // Minimum similarity for a word to be considered a match. Mobile STT is
  // strong but rephrases/splits words, so iOS uses a more lenient threshold
  // than the desktop reference.
  static const double _matchThreshold = 0.55;
  // Lenient threshold for the fast single-word path on mobile.
  static const double _fastMatchThreshold = 0.65;
  // Penalty applied per word of distance from the current position.
  static const double _distancePenaltyPerWord = 0.025;
  // Cross-language (e.g. Latin word in Hebrew script) - more lenient
  // Hebrew-specific: even more lenient because STT often returns approximate matches
  static const double _hebrewMatchThreshold = 0.50;
  // Bullet/header prompting must not silently walk through guessed words.
  static const double _strictMatchThreshold = 0.82;
  static const double _strictPhraseThreshold = 0.78;

  static bool isBigRecognitionWord(String normalizedWord,
          {int minLetters = 5}) =>
      normalizedWord.trim().length >= minLetters.clamp(1, 99);

  /// Parse raw script text into a list of ScriptWords.
  /// Preserves paragraph breaks as isNewline=true entries.
  static List<ScriptWord> tokenize(String text) =>
      _WordAlignerTokenizer.tokenize(text);

  static int nextSpeakableIndex(List<ScriptWord> script, int startIndex) {
    var i = startIndex.clamp(0, script.length).toInt();
    while (i < script.length &&
        (script[i].isNewline || _isUnspeakable(script[i]))) {
      i++;
    }
    return i;
  }

  static int nextRequiredSpeakableIndex(
      List<ScriptWord> script, int startIndex) {
    var i = startIndex.clamp(0, script.length).toInt();
    while (i < script.length &&
        (script[i].isNewline ||
            _isUnspeakable(script[i]) ||
            script[i].isOptionalCue)) {
      i++;
    }
    return i;
  }

  static double spokenWordSimilarity(String spoken, ScriptWord word) {
    if (word.normalized.isEmpty) return 0.0;
    return _wordSimilarity(spoken, word.normalized, word.isRtl);
  }

  static bool spokenWordMatchesNext(
    String spoken,
    ScriptWord word, {
    bool strictBulletMode = false,
  }) {
    if (spoken.isEmpty || word.normalized.isEmpty) return false;
    final threshold =
        strictBulletMode ? _strictMatchThreshold : (word.isRtl ? 0.45 : 0.55);
    return spokenWordSimilarity(spoken, word) >= threshold;
  }

  static int _localRecoveryWindowEnd(
    List<ScriptWord> script,
    int startIndex,
    int requiredSpeakableWords,
  ) {
    var counted = 0;
    var i = startIndex.clamp(0, script.length).toInt();
    while (i < script.length) {
      final word = script[i];
      if (!word.isNewline && !_isUnspeakable(word) && !word.isOptionalCue) {
        counted++;
      }
      i++;
      if (counted >= requiredSpeakableWords) return i;
    }
    return script.length;
  }

  // -- Aligner -----------------------------------------------------------------

  /// Core alignment: given a script word list and a speech transcript,
  /// determine which word the user has reached.
  ///
  /// Strategy:
  /// 1. FAST PATH: Check the very next expected word(s) first - if the last
  ///    spoken word matches the next script word, advance by exactly 1.
  /// 2. NEARBY SCAN: Check a small window (+/-8 words) for a strong single-word
  ///    match. This handles minor improvisation where the user skips 1-2 words.
  /// 3. MULTI-WORD CONFIRMATION: Use the last 3 spoken words to confirm a
  ///    position via sequence alignment. This prevents false matches on common
  ///    words appearing multiple times.
  ///
  /// Returns the best matching word index and a confidence score.
  static AlignmentResult align({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    int? visibleSkipStartIndex,
    int? maxSkipTargetIndex,
    bool strictBulletMode = false,
    SttRecognitionPolicy? policy,
    bool readingStandby = false,
  }) {
    if (script.isEmpty || transcript.trim().isEmpty) {
      return AlignmentResult(
          lastConfirmedIndex, 0.0, 'EMPTY', SttAlignmentDecision.wait);
    }

    final nonNL = script.where((w) => !w.isNewline).toList();
    if (nonNL.isEmpty) {
      return AlignmentResult(
          lastConfirmedIndex, 0.0, 'NO_WORDS', SttAlignmentDecision.wait);
    }

    // Preprocess transcript
    final rawWords = transcript
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().normalizeForMatching())
        .where((w) => w.isNotEmpty)
        .toList();

    final transcriptWords = _collapseAbbreviations(rawWords);
    if (transcriptWords.isEmpty) {
      return AlignmentResult(
          lastConfirmedIndex, 0.0, 'EMPTY_NORM', SttAlignmentDecision.wait);
    }

    final effectivePolicy = policy ??
        SttRecognitionPolicy.legacy(
          strictBulletMode: strictBulletMode,
          visibleSkipEnabled: maxSkipTargetIndex != null,
        );
    final policyBulletMode = effectivePolicy.bulletMode || strictBulletMode;
    final activeStandby = readingStandby || policyBulletMode;
    final localThreshold =
        effectivePolicy.localThreshold(readingStandby: activeStandby);
    final visibleThreshold = effectivePolicy.visibleSkip;
    final transcriptPassesLocal = localThreshold.passes(transcriptWords);
    final transcriptPassesVisible = visibleThreshold.passes(transcriptWords);

    final lastSpoken = transcriptWords.last;

    // Find the search start: skip over newlines AND unspeakable tokens
    // (numbers, dates, punctuation that STT won't produce reliably)
    final searchStart = nextSpeakableIndex(script, lastConfirmedIndex + 1);
    if (searchStart >= script.length) {
      return AlignmentResult(
          lastConfirmedIndex, 0.0, 'AT_END', SttAlignmentDecision.wait);
    }

    // Default allows small local recovery for missed STT words. Larger
    // paragraph/section skips remain opt-in and viewport-bound.
    final visibleMaxSkipTargetIndex = maxSkipTargetIndex;
    final visibleSkipEnabled =
        visibleMaxSkipTargetIndex != null && effectivePolicy.visibleSkipEnabled;
    final strictEnd = searchStart + 1;
    const localRecoveryWords = _maxSingleJump;
    final defaultLocalRecoveryEnd =
        _localRecoveryWindowEnd(script, searchStart, localRecoveryWords)
            .clamp(strictEnd, script.length)
            .toInt();
    final allowedEnd = visibleMaxSkipTargetIndex == null
        ? defaultLocalRecoveryEnd
        : (visibleMaxSkipTargetIndex + 1).clamp(strictEnd, script.length);
    final scanEnd =
        visibleSkipEnabled ? allowedEnd : searchStart + _searchWindowSize;
    final windowEnd = scanEnd.clamp(0, allowedEnd).toInt();
    final visibleScanStart = visibleSkipEnabled
        ? (visibleSkipStartIndex ?? searchStart)
            .clamp(searchStart, windowEnd)
            .toInt()
        : searchStart;

    AlignmentResult? earlyDirectNextWord(int candidateIndex) {
      if (candidateIndex >= script.length ||
          script[candidateIndex].isNewline ||
          _isUnspeakable(script[candidateIndex])) {
        return null;
      }
      final nextWord = script[candidateIndex].normalized;
      final isHebrew = script[candidateIndex].isRtl;
      final sim = _wordSimilarity(lastSpoken, nextWord, isHebrew);
      final lowEvidenceThreshold =
          policyBulletMode ? _strictMatchThreshold : (isHebrew ? 0.62 : 0.72);
      if (sim < lowEvidenceThreshold) return null;
      final skippedCue =
          candidateIndex != searchStart ? ' optionalCueSkip' : '';
      return AlignmentResult(
        candidateIndex,
        sim,
        'NEXT_WORD_LOW_EVIDENCE$skippedCue: "$lastSpoken" ~ "$nextWord" = ${sim.toStringAsFixed(2)}',
      );
    }

    if (!policyBulletMode &&
        activeStandby &&
        !transcriptPassesLocal &&
        !(visibleSkipEnabled && transcriptPassesVisible)) {
      final directNext = earlyDirectNextWord(searchStart);
      if (directNext != null) return directNext;
      if (script[searchStart].isOptionalCue) {
        final requiredStart =
            nextRequiredSpeakableIndex(script, searchStart + 1);
        final requiredNext = earlyDirectNextWord(requiredStart);
        if (requiredNext != null) return requiredNext;
      }
    }

    if (!transcriptPassesLocal &&
        !(visibleSkipEnabled && transcriptPassesVisible)) {
      if (!activeStandby) {
        final standbyMatch = _nearbyPhrasePriorityMatch(
          script: script,
          transcriptWords: transcriptWords,
          searchStart: searchStart,
          windowEnd: defaultLocalRecoveryEnd,
          lastConfirmedIndex: lastConfirmedIndex,
          maxPhraseWords: 2,
          maxJump: _maxSingleJump,
          minPhraseWords: 2,
          evidenceThreshold: const SttEvidenceThreshold(2),
          minPhraseScore: _matchThreshold,
          debugPrefix: 'STANDBY_LOCK',
        );
        if (standbyMatch != null) {
          return AlignmentResult(
            lastConfirmedIndex,
            standbyMatch.confidence,
            standbyMatch.debugInfo,
            SttAlignmentDecision.standby,
          );
        }
      }

      return AlignmentResult(
        lastConfirmedIndex,
        0.0,
        'WAIT_EVIDENCE: local=${localThreshold.label} visible=${visibleThreshold.label} heard=${transcriptWords.length}',
        SttAlignmentDecision.wait,
      );
    }

    // -- STEP 1: NEXT-WORD PRIORITY ------------------------------------------
    // The most common case: user said the very next word. Check it first with
    // a slightly lower threshold since position makes it very likely.
    AlignmentResult? nextWordPriority(int candidateIndex) {
      final canAdvanceOneWord =
          activeStandby || localThreshold.passes([lastSpoken]);
      if (!canAdvanceOneWord ||
          candidateIndex >= script.length ||
          script[candidateIndex].isNewline ||
          _isUnspeakable(script[candidateIndex])) {
        return null;
      }
      final nextWord = script[candidateIndex].normalized;
      final isHebrew = script[candidateIndex].isRtl;
      final sim = _wordSimilarity(lastSpoken, nextWord, isHebrew);
      final nextThreshold =
          policyBulletMode ? _strictMatchThreshold : (isHebrew ? 0.45 : 0.55);
      if (sim < nextThreshold) return null;
      final skippedCue =
          candidateIndex != searchStart ? ' optionalCueSkip' : '';
      return AlignmentResult(candidateIndex, sim,
          'NEXT_WORD$skippedCue: "$lastSpoken" ~ "$nextWord" = ${sim.toStringAsFixed(2)}');
    }

    final directNext = nextWordPriority(searchStart);
    if (directNext != null) return directNext;
    if (script[searchStart].isOptionalCue) {
      final requiredStart = nextRequiredSpeakableIndex(script, searchStart + 1);
      final requiredNext = nextWordPriority(requiredStart);
      if (requiredNext != null) return requiredNext;
    }

    // -- STEP 2: NEARBY SINGLE-WORD SCAN -------------------------------------
    // Look at a small window ahead for a strong single-word match.
    String debugScans = '';
    double bestSingleSim = 0.0;
    int bestSingleIdx = -1;

    for (int i = searchStart; i < windowEnd; i++) {
      if (script[i].isNewline) continue;
      final scriptWord = script[i].normalized;
      if (scriptWord.isEmpty) continue;

      final sim = _wordSimilarity(lastSpoken, scriptWord, script[i].isRtl);
      final distance = i - searchStart;
      // Apply distance penalty - farther words need higher confidence
      final adjustedSim = sim - (distance * _distancePenaltyPerWord);

      debugScans +=
          '  [$i]"$scriptWord" sim=${sim.toStringAsFixed(2)} adj=${adjustedSim.toStringAsFixed(2)}\n';

      if (adjustedSim > bestSingleSim) {
        bestSingleSim = adjustedSim;
        bestSingleIdx = i;
      }
    }

    if (bestSingleIdx >= 0) {
      // Use lower threshold for Hebrew words since STT is less precise
      final bestIsHebrew =
          bestSingleIdx < script.length && script[bestSingleIdx].isRtl;
      final singleThreshold =
          bestIsHebrew ? _hebrewMatchThreshold : _fastMatchThreshold;
      final effectiveSingleThreshold =
          policyBulletMode ? _strictMatchThreshold : singleThreshold;
      if (bestSingleSim >= effectiveSingleThreshold) {
        final allowSingleAdvance =
            activeStandby && localThreshold.passes([lastSpoken]);
        if (allowSingleAdvance && bestSingleIdx == searchStart) {
          return AlignmentResult(bestSingleIdx, bestSingleSim,
              'SINGLE: "$lastSpoken" -> [$bestSingleIdx]"${script[bestSingleIdx].normalized}" = ${bestSingleSim.toStringAsFixed(2)}\n$debugScans');
        }
      }
    }

    final nextPhrase = _contiguousNextPhraseMatch(
      script: script,
      transcriptWords: transcriptWords,
      searchStart: searchStart,
      lastConfirmedIndex: lastConfirmedIndex,
      maxPhraseWords: _localRecoveryPhraseMaxWords,
      evidenceThreshold: policyBulletMode
          ? effectivePolicy.bulletAdvance
          : effectivePolicy.safetyRecovery,
      overrideWordThreshold: policyBulletMode ? _strictPhraseThreshold : null,
      minPhraseScore: policyBulletMode ? _strictPhraseThreshold : 0.70,
    );
    if (nextPhrase != null) return nextPhrase;

    final localPhrase = _nearbyPhrasePriorityMatch(
      script: script,
      transcriptWords: transcriptWords,
      searchStart: searchStart,
      windowEnd: defaultLocalRecoveryEnd,
      lastConfirmedIndex: lastConfirmedIndex,
      maxPhraseWords: _localRecoveryPhraseMaxWords,
      maxJump: _maxSingleJump,
      minPhraseWords: localThreshold.bigWords,
      evidenceThreshold: localThreshold,
      overrideWordThreshold: policyBulletMode ? _strictPhraseThreshold : null,
      minPhraseScore:
          policyBulletMode ? _strictPhraseThreshold : _matchThreshold,
      debugPrefix: 'LOCAL_RECOVERY_PHRASE',
    );
    if (localPhrase != null) return localPhrase;

    if (visibleSkipEnabled) {
      final nearbyPhrase = _nearbyPhrasePriorityMatch(
        script: script,
        transcriptWords: transcriptWords,
        searchStart: visibleScanStart,
        windowEnd: windowEnd,
        lastConfirmedIndex: lastConfirmedIndex,
        scanFullWindow: true,
        scanAllTranscriptPhrases: policyBulletMode,
        minPhraseWords: visibleThreshold.bigWords,
        evidenceThreshold: visibleThreshold,
        scriptGapThreshold: effectivePolicy.safetyRecovery,
        overrideWordThreshold: policyBulletMode ? _strictPhraseThreshold : null,
        minPhraseScore:
            policyBulletMode ? _strictPhraseThreshold : _matchThreshold,
        debugPrefix: 'NEAR_PHRASE_PRIORITY',
      );
      if (nearbyPhrase != null) return nearbyPhrase;
    }

    // -- STEP 3: MULTI-WORD SEQUENCE CONFIRMATION ----------------------------
    // Use the last K spoken words to find a matching sequence in the script.
    // This helps confirm position when single words are ambiguous.
    final k = visibleSkipEnabled
        ? visibleThreshold.smallWords
        : localThreshold.smallWords;
    final recentWords = transcriptWords.length > k
        ? transcriptWords.sublist(transcriptWords.length - k)
        : transcriptWords;

    double bestSeqScore = 0.0;
    int bestSeqEndIdx = lastConfirmedIndex;
    int bestSeqStartIdx = -1;
    String bestSeqDebug = '';

    final seqSearchStart = visibleSkipEnabled ? visibleScanStart : searchStart;
    for (int i = seqSearchStart; i < windowEnd; i++) {
      if (script[i].isNewline) continue;
      int matchCount = 0;
      double seqScore = 0.0;
      int si = i;
      final sequenceEnd = visibleSkipEnabled ? windowEnd : script.length;

      for (int j = 0; j < recentWords.length && si < sequenceEnd; si++) {
        if (script[si].isNewline || _isUnspeakable(script[si])) continue;
        final scriptWord = script[si].normalized;
        final spokenWord = recentWords[j];

        final sim = _wordSimilarity(spokenWord, scriptWord, script[si].isRtl);
        final threshold = policyBulletMode
            ? _strictPhraseThreshold
            : (script[si].isRtl ? _hebrewMatchThreshold : _matchThreshold);
        if (sim >= threshold) {
          seqScore += sim;
          matchCount++;
        } else if (script[si].isOptionalCue) {
          continue;
        }
        j++;
      }

      final distance = i - seqSearchStart;
      final distPenalty = visibleSkipEnabled
          ? (distance * _distancePenaltyPerWord).clamp(0.0, 0.20)
          : distance * _distancePenaltyPerWord;
      final available = recentWords.length;
      final normalizedScore =
          available > 0 ? (seqScore / available) - distPenalty : 0.0;

      final candidateDistance = i - seqSearchStart;
      final bestDistance = bestSeqStartIdx < 0
          ? 1 << 30
          : (bestSeqStartIdx - seqSearchStart).abs();
      final clearlyBetter = normalizedScore > bestSeqScore + 0.06;
      final nearTieButCloser = (normalizedScore - bestSeqScore).abs() <= 0.06 &&
          candidateDistance < bestDistance;
      if ((clearlyBetter || nearTieButCloser) && matchCount >= 1) {
        final seqJump = (si - 1) - lastConfirmedIndex;
        final maxSeqJump = visibleMaxSkipTargetIndex == null
            ? _maxSingleJump
            : (visibleMaxSkipTargetIndex - lastConfirmedIndex)
                .clamp(0, script.length)
                .toInt();
        // For large jumps, require at least 2 matching words for confidence
        final thresholdForSeq =
            visibleSkipEnabled ? visibleThreshold : localThreshold;
        final matchedWords = recentWords.take(matchCount);
        if (thresholdForSeq.passes(matchedWords) && seqJump <= maxSeqJump) {
          bestSeqScore = normalizedScore;
          bestSeqStartIdx = i;
          bestSeqEndIdx = (si - 1).clamp(lastConfirmedIndex, script.length - 1);
          bestSeqDebug =
              'SEQ@$i: matched=$matchCount/$available score=${normalizedScore.toStringAsFixed(2)} end=$bestSeqEndIdx jump=$seqJump nearest=${candidateDistance < bestDistance}';
        }
      }
    }

    final minSeqScore =
        policyBulletMode ? _strictPhraseThreshold : _matchThreshold;
    if (bestSeqScore >= minSeqScore && bestSeqEndIdx > lastConfirmedIndex) {
      return AlignmentResult(
          bestSeqEndIdx, bestSeqScore, '$bestSeqDebug\n$debugScans');
    }

    // -- NO MATCH ------------------------------------------------------------
    // The spoken word didn't match anything in our window. This is normal
    // during improvisation - the user is saying something not in the script.
    final nextExpected =
        searchStart < script.length ? script[searchStart].normalized : '?';
    return AlignmentResult(
      lastConfirmedIndex,
      bestSingleSim.clamp(0.0, 1.0),
      'NO_MATCH: heard="$lastSpoken" expected="$nextExpected" bestSim=${bestSingleSim.toStringAsFixed(2)}\n$debugScans',
      SttAlignmentDecision.wait,
    );
  }

  static AlignmentResult? _nearbyPhrasePriorityMatch({
    required List<ScriptWord> script,
    required List<String> transcriptWords,
    required int searchStart,
    required int windowEnd,
    required int lastConfirmedIndex,
    int maxPhraseWords = _nearPhraseMaxWords,
    int? maxJump,
    int minPhraseWords = 3,
    SttEvidenceThreshold? evidenceThreshold,
    SttEvidenceThreshold? scriptGapThreshold,
    bool scanFullWindow = false,
    bool scanAllTranscriptPhrases = false,
    double? overrideWordThreshold,
    double minPhraseScore = _matchThreshold,
    String debugPrefix = 'NEAR_PHRASE_PRIORITY',
  }) {
    if (transcriptWords.length < minPhraseWords) return null;

    final phraseWindowEnd = scanFullWindow
        ? windowEnd
        : (searchStart + _nearPhrasePriorityWindow)
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
          ? [
              for (var i = transcriptWords.length - phraseLen; i >= 0; i--) i,
            ]
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

          for (int j = 0;
              j < spokenPhrase.length && si < phraseWindowEnd;
              si++) {
            if (script[si].isNewline || _isUnspeakable(script[si])) {
              continue;
            }

            final scriptWord = script[si].normalized;
            final sim =
                _wordSimilarity(spokenPhrase[j], scriptWord, script[si].isRtl);
            final threshold = overrideWordThreshold ??
                (script[si].isRtl ? _hebrewMatchThreshold : _matchThreshold);
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
        return AlignmentResult(phraseBestEnd, phraseBestScore,
            '$debugPrefix@$phraseBestStart: words=$phraseLen transcript=$phraseBestTranscriptStart end=$phraseBestEnd score=${phraseBestScore.toStringAsFixed(2)} gapCost=${phraseBestGapCost.toStringAsFixed(1)}');
      }
    }

    return null;
  }

  static AlignmentResult? _contiguousNextPhraseMatch({
    required List<ScriptWord> script,
    required List<String> transcriptWords,
    required int searchStart,
    required int lastConfirmedIndex,
    required int maxPhraseWords,
    required SttEvidenceThreshold evidenceThreshold,
    double? overrideWordThreshold,
    double minPhraseScore = _matchThreshold,
  }) {
    if (transcriptWords.length < 2 || searchStart >= script.length) {
      return null;
    }

    final longest = [
      maxPhraseWords,
      transcriptWords.length,
    ].reduce((a, b) => a < b ? a : b);

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
            (scriptWord.isRtl ? _hebrewMatchThreshold : _matchThreshold);
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
        );
      }
    }

    return null;
  }
}
