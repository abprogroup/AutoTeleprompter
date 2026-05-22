import 'package:flutter/material.dart';
import '../../script/models/script_word.dart';
import '../../../core/extensions/string_extensions.dart';

part 'word_aligner.markup_parser.dart';

class AlignmentResult {
  final int confirmedWordIndex;
  final double confidence;
  final String debugInfo; // detailed debug info about match decision
  AlignmentResult(this.confirmedWordIndex, this.confidence,
      [this.debugInfo = '']);
}

class WordAligner {
  // â”€â”€ Tuning constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Window size to search ahead (in non-newline words).
  static const int _searchWindowSize = 50;
  // Max words for a SINGLE-word match (prevents false jumps on common words).
  static const int _maxSingleJump = 5;
  // Nearby phrase window checked before the visible-skip fallback.
  static const int _nearPhrasePriorityWindow = 50;
  static const int _nearPhraseMaxWords = 8;
  static const int _localRecoveryPhraseMaxWords = 5;
  // Minimum similarity for a word to be considered a match
  static const double _matchThreshold = 0.55;
  // Stricter threshold for the fast single-word path
  static const double _fastMatchThreshold = 0.65;
  // Penalty applied per word of distance from the current position.
  static const double _distancePenaltyPerWord = 0.025;
  // Cross-language (e.g. Latin word in Hebrew script) â€” more lenient
  static const double _crossLangThreshold = 0.45;
  // Hebrew-specific: even more lenient because STT often returns approximate matches
  static const double _hebrewMatchThreshold = 0.50;
  // Bullet/header prompting must not silently walk through guessed words.
  static const double _strictMatchThreshold = 0.82;
  static const double _strictPhraseThreshold = 0.78;
  static const int _normalModeMinTranscriptWords = 3;

  /// Parse raw script text into a list of ScriptWords.
  /// Preserves paragraph breaks as isNewline=true entries.
  static List<ScriptWord> tokenize(String text) {
    final words = <ScriptWord>[];
    int index = 0;

    final lines = text.split('\n');

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];

      if (line.trim().isEmpty) {
        words.add(ScriptWord(
          raw: '\n\n', // v3.9.5.5: Hard break marker
          normalized: '',
          index: index++,
          isRtl: false,
          isNewline: true,
        ));
      } else {
        final parsed = _parseMarkup(line);

        for (final token in parsed) {
          final clean = token.text.trim();
          if (clean.isEmpty) continue;

          final parts =
              _mergeStandaloneNeutralParts(clean.split(RegExp(r'\s+')));
          for (final part in parts) {
            if (part.isEmpty) continue;
            // v3.9.7: Strip residual markup tags before RTL detection AND normalization
            // so [color=#HEX] etc. don't dilute the Hebrew character ratio
            final cleanPart = part.replaceAll(
                RegExp(
                    r'\[\/?(u|i|color|bg|font|size|align|center|left|right|rtl|ltr)(?:=[^\]]+)?\]|\*\*'),
                '');
            final isRtl = cleanPart.isHebrew;
            final normalized = cleanPart.normalizeForMatching();
            if (normalized.isEmpty &&
                _isStandaloneNeutralPunctuation(cleanPart)) {
              continue;
            }
            if (normalized.isEmpty && cleanPart.trim().isEmpty) continue;
            words.add(ScriptWord(
              raw: part,
              normalized: normalized,
              index: index++,
              isRtl: isRtl,
              isBold: token.isBold,
              isUnderline: token.isUnderline,
              fontSize: token.fontSize,
              alignment: token.alignment,
              isItalic: token.isItalic,
              isParagraphRtl: token.isParagraphRtl,
              highlight: token.highlight,
              textColor: token.textColor,
            ));
          }
        }

        // v3.9.5.3: Preserve single newlines as paragraph breaks
        if (li < lines.length - 1) {
          words.add(ScriptWord(
            raw: '\n', // v3.9.5.5: Soft break marker
            normalized: '',
            index: index++,
            isRtl: false,
            isNewline: true,
          ));
        }
      }
    }
    return words;
  }

  static List<String> _mergeStandaloneNeutralParts(Iterable<String> parts) {
    final merged = <String>[];
    var pendingOpen = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      if (_isStandaloneOpeningNeutral(part)) {
        pendingOpen += part;
        continue;
      }
      if (_isStandaloneClosingNeutral(part) && merged.isNotEmpty) {
        merged[merged.length - 1] = merged.last + part;
        continue;
      }
      merged.add(pendingOpen + part);
      pendingOpen = '';
    }
    if (pendingOpen.isNotEmpty && merged.isNotEmpty) {
      merged[merged.length - 1] = merged.last + pendingOpen;
    } else if (pendingOpen.isNotEmpty) {
      merged.add(pendingOpen);
    }
    return merged;
  }

  static bool _isStandaloneNeutralPunctuation(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\[\]\(\)\{\}\.,:;!?]+$').hasMatch(trimmed);
  }

  static bool _isStandaloneOpeningNeutral(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty && RegExp(r'^[\[\(\{]+$').hasMatch(trimmed);
  }

  static bool _isStandaloneClosingNeutral(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\]\)\}\.,:;!?]+$').hasMatch(trimmed);
  }

  // â”€â”€ Markup parser â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Returns the best matching word index and a confidence score.
  static AlignmentResult align({
    required List<ScriptWord> script,
    required String transcript,
    required int lastConfirmedIndex,
    int? visibleSkipStartIndex,
    int? maxSkipTargetIndex,
    bool strictBulletMode = false,
  }) {
    if (script.isEmpty || transcript.trim().isEmpty) {
      return AlignmentResult(lastConfirmedIndex, 0.0, 'EMPTY');
    }

    final nonNL = script.where((w) => !w.isNewline).toList();
    if (nonNL.isEmpty)
      return AlignmentResult(lastConfirmedIndex, 0.0, 'NO_WORDS');

    // Preprocess transcript
    final rawWords = transcript
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().normalizeForMatching())
        .where((w) => w.isNotEmpty)
        .toList();

    final transcriptWords = _collapseAbbreviations(rawWords);
    if (transcriptWords.isEmpty)
      return AlignmentResult(lastConfirmedIndex, 0.0, 'EMPTY_NORM');

    if (!strictBulletMode &&
        transcriptWords.length < _normalModeMinTranscriptWords) {
      return AlignmentResult(
        lastConfirmedIndex,
        0.0,
        'WAIT_MIN_WORDS: ${transcriptWords.length}/$_normalModeMinTranscriptWords',
      );
    }

    final lastSpoken = transcriptWords.last;

    // Find the search start: skip over newlines AND unspeakable tokens
    // (numbers, dates, punctuation that STT won't produce reliably)
    int searchStart = lastConfirmedIndex + 1;
    while (searchStart < script.length &&
        (script[searchStart].isNewline ||
            _isUnspeakable(script[searchStart]))) {
      searchStart++;
    }
    if (searchStart >= script.length) {
      return AlignmentResult(lastConfirmedIndex, 0.0, 'AT_END');
    }

    // Default allows small local recovery for missed STT words. Larger
    // paragraph/section skips remain opt-in and viewport-bound.
    final visibleMaxSkipTargetIndex = maxSkipTargetIndex;
    final visibleSkipEnabled = visibleMaxSkipTargetIndex != null;
    final strictEnd = searchStart + 1;
    final localRecoveryWords = strictBulletMode ? 1 : _maxSingleJump;
    final defaultLocalRecoveryEnd = (searchStart + localRecoveryWords)
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

    // â”€â”€ STEP 1: NEXT-WORD PRIORITY â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // The most common case: user said the very next word. Check it first with
    // a slightly lower threshold since position makes it very likely.
    if (searchStart < script.length && !script[searchStart].isNewline) {
      final nextWord = script[searchStart].normalized;
      if (nextWord.isNotEmpty) {
        final isHebrew = script[searchStart].isRtl;
        final sim = _wordSimilarity(lastSpoken, nextWord, isHebrew);
        // Hebrew STT is less precise â€” use a lower threshold for the next word
        final nextThreshold =
            strictBulletMode ? _strictMatchThreshold : (isHebrew ? 0.45 : 0.55);
        if (sim >= nextThreshold) {
          return AlignmentResult(searchStart, sim,
              'NEXT_WORD: "${lastSpoken}" ~ "${nextWord}" = ${sim.toStringAsFixed(2)}');
        }
      }
    }

    // â”€â”€ STEP 2: NEARBY SINGLE-WORD SCAN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
      // Apply distance penalty â€” farther words need higher confidence
      final adjustedSim = sim - (distance * _distancePenaltyPerWord);

      debugScans +=
          '  [${i}]"${scriptWord}" sim=${sim.toStringAsFixed(2)} adj=${adjustedSim.toStringAsFixed(2)}\n';

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
          strictBulletMode ? _strictMatchThreshold : singleThreshold;
      if (bestSingleSim >= effectiveSingleThreshold) {
        final jumpDist = bestSingleIdx - lastConfirmedIndex;
        // Single-word matches only allow small jumps to prevent false skips
        final maxSingleJump = strictBulletMode ? 1 : _maxSingleJump;
        if (jumpDist <= maxSingleJump) {
          return AlignmentResult(bestSingleIdx, bestSingleSim,
              'SINGLE: "${lastSpoken}" â†’ [${bestSingleIdx}]"${script[bestSingleIdx].normalized}" = ${bestSingleSim.toStringAsFixed(2)}\n$debugScans');
        }
      }
    }

    final localPhrase = _nearbyPhrasePriorityMatch(
      script: script,
      transcriptWords: transcriptWords,
      searchStart: searchStart,
      windowEnd: defaultLocalRecoveryEnd,
      lastConfirmedIndex: lastConfirmedIndex,
      maxPhraseWords: _localRecoveryPhraseMaxWords,
      maxJump: strictBulletMode ? 1 : _maxSingleJump,
      minPhraseWords: 2,
      overrideWordThreshold: strictBulletMode ? _strictPhraseThreshold : null,
      minPhraseScore:
          strictBulletMode ? _strictPhraseThreshold : _matchThreshold,
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
        scanAllTranscriptPhrases: strictBulletMode,
        minPhraseWords: strictBulletMode ? 2 : 3,
        overrideWordThreshold: strictBulletMode ? _strictPhraseThreshold : null,
        minPhraseScore:
            strictBulletMode ? _strictPhraseThreshold : _matchThreshold,
        debugPrefix: 'NEAR_PHRASE_PRIORITY',
      );
      if (nearbyPhrase != null) return nearbyPhrase;
    }

    // â”€â”€ STEP 3: MULTI-WORD SEQUENCE CONFIRMATION â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Use the last K spoken words to find a matching sequence in the script.
    // This helps confirm position when single words are ambiguous.
    const k = 3;
    final recentWords = transcriptWords.length > k
        ? transcriptWords.sublist(transcriptWords.length - k)
        : transcriptWords;

    double bestSeqScore = 0.0;
    int bestSeqEndIdx = lastConfirmedIndex;
    String bestSeqDebug = '';

    final seqSearchStart = visibleSkipEnabled ? visibleScanStart : searchStart;
    for (int i = seqSearchStart; i < windowEnd; i++) {
      if (script[i].isNewline) continue;
      int matchCount = 0;
      double seqScore = 0.0;
      int si = i;
      final sequenceEnd = visibleSkipEnabled ? windowEnd : script.length;

      for (int j = 0; j < recentWords.length && si < sequenceEnd; si++) {
        if (script[si].isNewline) continue;
        final scriptWord = script[si].normalized;
        if (scriptWord.isEmpty) {
          j++;
          continue;
        }
        final spokenWord = recentWords[j];

        final sim = _wordSimilarity(spokenWord, scriptWord, script[si].isRtl);
        final threshold = strictBulletMode
            ? _strictPhraseThreshold
            : (script[si].isRtl ? _hebrewMatchThreshold : _matchThreshold);
        if (sim >= threshold) {
          seqScore += sim;
          matchCount++;
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

      if (normalizedScore > bestSeqScore && matchCount >= 1) {
        final seqJump = (si - 1) - lastConfirmedIndex;
        final maxSeqJump = visibleMaxSkipTargetIndex == null
            ? _maxSingleJump
            : (visibleMaxSkipTargetIndex - lastConfirmedIndex)
                .clamp(0, script.length)
                .toInt();
        // For large jumps, require at least 2 matching words for confidence
        final minMatches = strictBulletMode
            ? (seqJump > 1 ? 2 : 1)
            : (seqJump > _maxSingleJump ? 2 : 1);
        if (matchCount >= minMatches && seqJump <= maxSeqJump) {
          bestSeqScore = normalizedScore;
          bestSeqEndIdx = (si - 1).clamp(lastConfirmedIndex, script.length - 1);
          bestSeqDebug =
              'SEQ@$i: matched=$matchCount/$available score=${normalizedScore.toStringAsFixed(2)} end=$bestSeqEndIdx jump=$seqJump';
        }
      }
    }

    final minSeqScore =
        strictBulletMode ? _strictPhraseThreshold : _matchThreshold;
    if (bestSeqScore >= minSeqScore && bestSeqEndIdx > lastConfirmedIndex) {
      return AlignmentResult(
          bestSeqEndIdx, bestSeqScore, '$bestSeqDebug\n$debugScans');
    }

    // â”€â”€ NO MATCH â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // The spoken word didn't match anything in our window. This is normal
    // during improvisation â€” the user is saying something not in the script.
    final nextExpected =
        searchStart < script.length ? script[searchStart].normalized : '?';
    return AlignmentResult(lastConfirmedIndex, bestSingleSim.clamp(0.0, 1.0),
        'NO_MATCH: heard="${lastSpoken}" expected="${nextExpected}" bestSim=${bestSingleSim.toStringAsFixed(2)}\n$debugScans');
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

      for (final transcriptStart in phraseStarts) {
        final spokenPhrase = transcriptWords.sublist(
          transcriptStart,
          transcriptStart + phraseLen,
        );
        if (!_hasUsefulPhraseWords(spokenPhrase, minPhraseWords)) continue;

        double bestScore = 0.0;
        int bestStart = -1;
        int bestEnd = -1;

        for (int i = searchStart; i < phraseWindowEnd; i++) {
          if (script[i].isNewline || script[i].normalized.isEmpty) continue;

          int si = i;
          int matched = 0;
          double score = 0.0;
          int endIdx = i;

          for (int j = 0;
              j < spokenPhrase.length && si < phraseWindowEnd;
              si++) {
            if (script[si].isNewline || script[si].normalized.isEmpty) {
              continue;
            }

            final sim = _wordSimilarity(
                spokenPhrase[j], script[si].normalized, script[si].isRtl);
            final threshold = overrideWordThreshold ??
                (script[si].isRtl ? _hebrewMatchThreshold : _matchThreshold);
            if (sim < threshold) break;

            matched++;
            score += sim;
            endIdx = si;
            j++;
          }

          if (matched != spokenPhrase.length) continue;

          final distance = i - searchStart;
          final adjustedScore =
              (score / spokenPhrase.length) - (distance * 0.006);
          if (adjustedScore > bestScore ||
              (adjustedScore == bestScore && i < bestStart)) {
            bestScore = adjustedScore;
            bestStart = i;
            bestEnd = endIdx;
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
        }
      }

      if (phraseBestStart >= 0) {
        return AlignmentResult(phraseBestEnd, phraseBestScore,
            '$debugPrefix@$phraseBestStart: words=$phraseLen transcript=$phraseBestTranscriptStart end=$phraseBestEnd score=${phraseBestScore.toStringAsFixed(2)}');
      }
    }

    return null;
  }

  static bool _hasUsefulPhraseWords(List<String> phrase, int minPhraseWords) {
    var useful = 0;
    for (final word in phrase) {
      if (!_phraseStopWords.contains(word)) useful++;
    }
    return useful >= (minPhraseWords == 2 ? 1 : 2);
  }

  static const Set<String> _phraseStopWords = {
    'a',
    'an',
    'and',
    'as',
    'at',
    'for',
    'in',
    'is',
    'of',
    'or',
    'the',
    'to',
    'we',
    'you',
  };

  // â”€â”€ Word similarity helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  /// Compute similarity between a spoken word and a script word,
  /// with special handling for Hebrew prefix stripping.
  static double _wordSimilarity(String spoken, String scriptWord, bool isRtl) {
    if (spoken == scriptWord) return 1.0;
    if (spoken.isEmpty || scriptWord.isEmpty) return 0.0;

    double sim = spoken.similarity(scriptWord);

    // For Hebrew words, try multiple matching strategies
    if (isRtl && sim < 0.75) {
      final ss = scriptWord.stripHebrewPrefixes();
      final ls = spoken.stripHebrewPrefixes();
      if (ss == ls || ss == spoken || scriptWord == ls) {
        sim = 0.88; // Strong match via prefix stripping
      } else {
        final prefixSim = ls.similarity(ss);
        if (prefixSim > sim) sim = prefixSim * 0.92;
      }

      // Also try phonetic normalization for Hebrew
      // (×›/×§, ×ª/×˜, ×‘/×•, ×—/×›, ×¡/×©×‚ are commonly confused by STT)
      if (sim < 0.65) {
        final phoneticSpoken = _hebrewPhonetic(spoken);
        final phoneticScript = _hebrewPhonetic(scriptWord);
        final phoneticSim = phoneticSpoken.similarity(phoneticScript);
        if (phoneticSim > sim) sim = phoneticSim * 0.90;

        // Also try phonetic + prefix strip
        final phoneticSS = _hebrewPhonetic(ss);
        final phoneticLS = _hebrewPhonetic(ls);
        final phoneticPrefixSim = phoneticLS.similarity(phoneticSS);
        if (phoneticPrefixSim > sim) sim = phoneticPrefixSim * 0.88;
      }

      // Substring match: if spoken word contains the script word or vice versa
      // (STT sometimes concatenates or splits Hebrew words)
      if (sim < 0.60) {
        if (ls.length >= 3 && ss.length >= 3) {
          if (ls.contains(ss) || ss.contains(ls)) {
            final overlapRatio =
                (ls.length < ss.length ? ls.length : ss.length) /
                    (ls.length > ss.length ? ls.length : ss.length);
            final subSim = 0.70 * overlapRatio + 0.20;
            if (subSim > sim) sim = subSim;
          }
        }
      }
    }

    return sim;
  }

  /// Normalize Hebrew letters that sound the same for phonetic comparison.
  static String _hebrewPhonetic(String s) {
    return s
        .replaceAll('\u05E7', '\u05DB') // ×§ â†’ ×›
        .replaceAll('\u05D8', '\u05EA') // ×˜ â†’ ×ª
        .replaceAll('\u05E1', '\u05E9') // ×¡ â†’ ×©
        .replaceAll('\u05E2', '\u05D0') // ×¢ â†’ ×
        .replaceAll('\u05D5', '\u05D1'); // ×• â†’ ×‘ (when confused by STT)
  }

  /// Collapse sequences of single-character words into abbreviation candidates.
  static List<String> _collapseAbbreviations(List<String> words) {
    if (words.length < 2) return words;
    final result = <String>[];
    int i = 0;
    while (i < words.length) {
      if (words[i].length == 1 && !words[i].isHebrew) {
        int j = i;
        while (j < words.length &&
            words[j].length == 1 &&
            !words[j].isHebrew &&
            j - i < 6) {
          j++;
        }
        if (j - i >= 2) {
          result.add(words.sublist(i, j).join(''));
        }
        result.addAll(words.sublist(i, j));
        i = j;
      } else {
        result.add(words[i]);
        i++;
      }
    }
    return result;
  }

  static bool _isUnspeakable(ScriptWord word) {
    if (word.isNewline) return true;
    final norm = word.normalized;
    if (norm.isEmpty) return true;
    // Numbers, dots, colons, dashes (e.g. 7.10.24, 20:30, 96, 12-34)
    if (RegExp(r'^[0-9\.:\-\/]+$').hasMatch(norm)) return true;
    return false;
  }
}
