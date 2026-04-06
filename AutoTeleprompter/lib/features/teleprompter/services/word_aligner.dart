import 'package:flutter/material.dart';
import '../../script/models/script_word.dart';
import '../../../core/extensions/string_extensions.dart';

class AlignmentResult {
  final int confirmedWordIndex;
  final double confidence;
  final String debugInfo; // detailed debug info about match decision
  AlignmentResult(this.confirmedWordIndex, this.confidence, [this.debugInfo = '']);
}

class WordAligner {
  // ── Tuning constants ───────────────────────────────────────────────────────
  // Window size to search ahead (in non-newline words).
  // Increased from 8 to 30 to allow matching anything visible on current screen.
  static const int _searchWindowSize = 30;
  // Max words to advance in a single update.
  // Increased from 3 to 10 to allow reading ahead over numbers/dates/punctuation.
  static const int _maxJumpWords = 10;
  // Minimum similarity for a word to be considered a match
  static const double _matchThreshold = 0.65;
  // Stricter threshold for the fast single-word path
  static const double _fastMatchThreshold = 0.75;
  // Penalty applied per word of distance from the current position.
  // Reduced to allow jumping to the next sentence more easily.
  static const double _distancePenaltyPerWord = 0.03;
  // Cross-language (e.g. Latin word in Hebrew script) — more lenient
  static const double _crossLangThreshold = 0.55;

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
          raw: '\n',
          normalized: '',
          index: index++,
          isRtl: false,
          isNewline: true,
        ));
        continue;
      }

      final parsed = _parseMarkup(line);

      for (final token in parsed) {
        final clean = token.text.trim();
        if (clean.isEmpty) continue;

        final parts = clean.split(RegExp(r'\s+'));
        for (final part in parts) {
          if (part.isEmpty) continue;
          final isRtl = part.isHebrew;
          final normalized = part.normalizeForMatching();
          if (normalized.isEmpty) continue;
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
    }
    return words;
  }

  // ── Markup parser ───────────────────────────────────────────────────────────

  static List<_Span> _parseMarkup(String line) {
    return _parseMarkupRecursive(line, const _Span(''));
  }

  // Recursive markup parser — supports nested tags (e.g. **[rc]word[/rc]**)
  static List<_Span> _parseMarkupRecursive(String text, _Span base) {
    final spans = <_Span>[];
    final pattern = RegExp(
      r'\*\*(.*?)\*\*'
      r'|\[y\](.*?)\[\/y\]'
      r'|\[r\](.*?)\[\/r\]'
      r'|\[g\](.*?)\[\/g\]'
      r'|\[b\](.*?)\[\/b\]'
      r'|\[o\](.*?)\[\/o\]'
      r'|\[p\](.*?)\[\/p\]'
      r'|\[c\](.*?)\[\/c\]'
      r'|\[pk\](.*?)\[\/pk\]'
      r'|\[yc\](.*?)\[\/yc\]'
      r'|\[rc\](.*?)\[\/rc\]'
      r'|\[gc\](.*?)\[\/gc\]'
      r'|\[bc\](.*?)\[\/bc\]'
      r'|\[oc\](.*?)\[\/oc\]'
      r'|\[pc\](.*?)\[\/pc\]'
      r'|\[cc\](.*?)\[\/cc\]'
      r'|\[pkc\](.*?)\[\/pkc\]'
      r'|\[u\](.*?)\[\/u\]'
      r'|\[size=(\d+)\](.*?)\[\/size\]'
      r'|\[(center|left|right)\](.*?)\[\/\1\]'
      r'|\[i\](.*?)\[\/i\]'
      r'|\[(rtl|ltr)\](.*?)\[\/\1\]',
      dotAll: true,
    );
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(_Span(text.substring(last, m.start),
            isBold: base.isBold, isUnderline: base.isUnderline, fontSize: base.fontSize, 
            alignment: base.alignment, isItalic: base.isItalic, isParagraphRtl: base.isParagraphRtl,
            highlight: base.highlight, textColor: base.textColor));
      }
      if (m.group(1) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(1)!,
            base.copyWith(text: '', isBold: true)));
      } else if (m.group(2) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(2)!,
            base.copyWith(text: '', highlight: Colors.yellow.withOpacity(0.6))));
      } else if (m.group(3) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(3)!,
            base.copyWith(text: '', highlight: Colors.red.withOpacity(0.55))));
      } else if (m.group(4) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(4)!,
            base.copyWith(text: '', highlight: Colors.green.withOpacity(0.55))));
      } else if (m.group(5) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(5)!,
            base.copyWith(text: '', highlight: Colors.blue.withOpacity(0.45))));
      } else if (m.group(6) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(6)!,
            base.copyWith(text: '', highlight: Colors.orange.withOpacity(0.50))));
      } else if (m.group(7) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(7)!,
            base.copyWith(text: '', highlight: Colors.purple.withOpacity(0.45))));
      } else if (m.group(8) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(8)!,
            base.copyWith(text: '', highlight: Colors.cyan.withOpacity(0.45))));
      } else if (m.group(9) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(9)!,
            base.copyWith(text: '', highlight: Colors.pink.withOpacity(0.45))));
      } else if (m.group(10) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(10)!,
            base.copyWith(text: '', textColor: Colors.yellow.shade300)));
      } else if (m.group(11) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(11)!,
            base.copyWith(text: '', textColor: Colors.red.shade300)));
      } else if (m.group(12) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(12)!,
            base.copyWith(text: '', textColor: Colors.greenAccent.shade200)));
      } else if (m.group(13) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(13)!,
            base.copyWith(text: '', textColor: Colors.blue.shade300)));
      } else if (m.group(14) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(14)!,
            base.copyWith(text: '', textColor: Colors.orange.shade300)));
      } else if (m.group(15) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(15)!,
            base.copyWith(text: '', textColor: Colors.purple.shade200)));
      } else if (m.group(16) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(16)!,
            base.copyWith(text: '', textColor: Colors.cyan.shade300)));
      } else if (m.group(17) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(17)!,
            base.copyWith(text: '', textColor: Colors.pink.shade300)));
      } else if (m.group(18) != null) {
        spans.addAll(_parseMarkupRecursive(m.group(18)!,
            base.copyWith(text: '', isUnderline: true)));
      } else if (m.group(19) != null && m.group(20) != null) {
        final sz = double.tryParse(m.group(19)!);
        spans.addAll(_parseMarkupRecursive(m.group(20)!,
            base.copyWith(text: '', fontSize: sz)));
      } else if (m.group(21) != null && m.group(22) != null) {
        // [center|left|right]
        final alignStr = m.group(21)!;
        TextAlign align = TextAlign.center;
        if (alignStr == 'left') align = TextAlign.left;
        if (alignStr == 'right') align = TextAlign.right;
        spans.addAll(_parseMarkupRecursive(m.group(22)!,
            base.copyWith(text: '', alignment: align)));
      } else if (m.group(23) != null) {
        // [i] italics
        spans.addAll(_parseMarkupRecursive(m.group(23)!,
            base.copyWith(text: '', isItalic: true)));
      } else if (m.group(24) != null && m.group(25) != null) {
        // [rtl|ltr]
        final dir = m.group(24)!;
        spans.addAll(_parseMarkupRecursive(m.group(25)!,
            base.copyWith(text: '', isParagraphRtl: dir == 'rtl')));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(_Span(text.substring(last),
          isBold: base.isBold, isUnderline: base.isUnderline, fontSize: base.fontSize, 
          isItalic: base.isItalic, highlight: base.highlight, textColor: base.textColor));
    }
    return spans;
  }

  // ── Aligner ─────────────────────────────────────────────────────────────────

  /// Core alignment: given a script word list and a speech transcript,
  /// determine which word the user has reached.
  ///
  /// Strategy:
  /// 1. FAST PATH: Check the very next expected word(s) first — if the last
  ///    spoken word matches the next script word, advance by exactly 1.
  /// 2. NEARBY SCAN: Check a small window (±8 words) for a strong single-word
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
  }) {
    if (script.isEmpty || transcript.trim().isEmpty) {
      return AlignmentResult(lastConfirmedIndex, 0.0, 'EMPTY');
    }

    final nonNL = script.where((w) => !w.isNewline).toList();
    if (nonNL.isEmpty) return AlignmentResult(lastConfirmedIndex, 0.0, 'NO_WORDS');

    // Preprocess transcript
    final rawWords = transcript
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().normalizeForMatching())
        .where((w) => w.isNotEmpty)
        .toList();

    final transcriptWords = _collapseAbbreviations(rawWords);
    if (transcriptWords.isEmpty) return AlignmentResult(lastConfirmedIndex, 0.0, 'EMPTY_NORM');

    final lastSpoken = transcriptWords.last;

    // Find the search start: skip over newlines AND unspeakable tokens
    // (numbers, dates, punctuation that STT won't produce reliably)
    int searchStart = lastConfirmedIndex + 1;
    while (searchStart < script.length && 
           (script[searchStart].isNewline || _isUnspeakable(script[searchStart]))) {
      searchStart++;
    }
    if (searchStart >= script.length) {
      return AlignmentResult(lastConfirmedIndex, 0.0, 'AT_END');
    }

    // Use a wider window to look past clusters of numbers/dates
    final windowEnd = (searchStart + 15).clamp(0, script.length);

    // ── STEP 1: NEXT-WORD PRIORITY ──────────────────────────────────────────
    // The most common case: user said the very next word. Check it first with
    // a slightly lower threshold since position makes it very likely.
    if (searchStart < script.length && !script[searchStart].isNewline) {
      final nextWord = script[searchStart].normalized;
      if (nextWord.isNotEmpty) {
        final sim = _wordSimilarity(lastSpoken, nextWord, script[searchStart].isRtl);
        if (sim >= 0.60) {
          return AlignmentResult(searchStart, sim,
              'NEXT_WORD: "${lastSpoken}" ~ "${nextWord}" = ${sim.toStringAsFixed(2)}');
        }
      }
    }

    // ── STEP 2: NEARBY SINGLE-WORD SCAN ─────────────────────────────────────
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
      // Apply distance penalty — farther words need higher confidence
      final adjustedSim = sim - (distance * _distancePenaltyPerWord);

      debugScans += '  [${i}]"${scriptWord}" sim=${sim.toStringAsFixed(2)} adj=${adjustedSim.toStringAsFixed(2)}\n';

      if (adjustedSim > bestSingleSim) {
        bestSingleSim = adjustedSim;
        bestSingleIdx = i;
      }
    }

    if (bestSingleIdx >= 0 && bestSingleSim >= _fastMatchThreshold) {
      final jumpDist = bestSingleIdx - lastConfirmedIndex;
      if (jumpDist <= _maxJumpWords) {
        return AlignmentResult(bestSingleIdx, bestSingleSim,
            'SINGLE: "${lastSpoken}" → [${bestSingleIdx}]"${script[bestSingleIdx].normalized}" = ${bestSingleSim.toStringAsFixed(2)}\n$debugScans');
      }
    }

    // ── STEP 3: MULTI-WORD SEQUENCE CONFIRMATION ────────────────────────────
    // Use the last K spoken words to find a matching sequence in the script.
    // This helps confirm position when single words are ambiguous.
    const k = 3;
    final recentWords = transcriptWords.length > k
        ? transcriptWords.sublist(transcriptWords.length - k)
        : transcriptWords;

    double bestSeqScore = 0.0;
    int bestSeqEndIdx = lastConfirmedIndex;
    String bestSeqDebug = '';

    for (int i = searchStart; i < windowEnd; i++) {
      if (script[i].isNewline) continue;
      int matchCount = 0;
      double seqScore = 0.0;
      int si = i;

      for (int j = 0; j < recentWords.length && si < script.length; si++) {
        if (script[si].isNewline) continue;
        final scriptWord = script[si].normalized;
        if (scriptWord.isEmpty) { j++; continue; }
        final spokenWord = recentWords[j];

        final sim = _wordSimilarity(spokenWord, scriptWord, script[si].isRtl);
        if (sim >= _matchThreshold) {
          seqScore += sim;
          matchCount++;
        }
        j++;
      }

      final distance = i - searchStart;
      final distPenalty = distance * _distancePenaltyPerWord;
      final available = recentWords.length;
      final normalizedScore = available > 0 ? (seqScore / available) - distPenalty : 0.0;

      if (normalizedScore > bestSeqScore && matchCount >= 1) {
        bestSeqScore = normalizedScore;
        // Return the position of the LAST matched word in the sequence
        // (i.e. the furthest confirmed position), but cap the jump
        bestSeqEndIdx = (si - 1).clamp(lastConfirmedIndex, script.length - 1);
        bestSeqDebug = 'SEQ@$i: matched=$matchCount/$available score=${normalizedScore.toStringAsFixed(2)} end=$bestSeqEndIdx';
      }
    }

    if (bestSeqScore >= _matchThreshold && bestSeqEndIdx > lastConfirmedIndex) {
      final jumpDist = bestSeqEndIdx - lastConfirmedIndex;
      // Only allow sequence jumps within the max jump limit, or with very high confidence
      if (jumpDist <= _maxJumpWords || (bestSeqScore >= 0.90 && jumpDist <= _maxJumpWords + 2)) {
        return AlignmentResult(bestSeqEndIdx, bestSeqScore,
            '$bestSeqDebug\n$debugScans');
      }
    }

    // ── NO MATCH ────────────────────────────────────────────────────────────
    // The spoken word didn't match anything in our window. This is normal
    // during improvisation — the user is saying something not in the script.
    final nextExpected = searchStart < script.length ? script[searchStart].normalized : '?';
    return AlignmentResult(lastConfirmedIndex, bestSingleSim.clamp(0.0, 1.0),
        'NO_MATCH: heard="${lastSpoken}" expected="${nextExpected}" bestSim=${bestSingleSim.toStringAsFixed(2)}\n$debugScans');
  }

  // ── Word similarity helper ─────────────────────────────────────────────────
  /// Compute similarity between a spoken word and a script word,
  /// with special handling for Hebrew prefix stripping.
  static double _wordSimilarity(String spoken, String scriptWord, bool isRtl) {
    if (spoken == scriptWord) return 1.0;
    if (spoken.isEmpty || scriptWord.isEmpty) return 0.0;

    double sim = spoken.similarity(scriptWord);

    // For Hebrew words, also try with stripped prefixes
    if (isRtl && sim < 0.75) {
      final ss = scriptWord.stripHebrewPrefixes();
      final ls = spoken.stripHebrewPrefixes();
      if (ss == ls || ss == spoken || scriptWord == ls) {
        sim = 0.88; // Strong match via prefix stripping
      } else {
        final prefixSim = ls.similarity(ss);
        if (prefixSim > sim) sim = prefixSim * 0.92; // Slight penalty for prefix match
      }
    }

    return sim;
  }

  /// Collapse sequences of single-character words into abbreviation candidates.
  static List<String> _collapseAbbreviations(List<String> words) {
    if (words.length < 2) return words;
    final result = <String>[];
    int i = 0;
    while (i < words.length) {
      if (words[i].length == 1 && !words[i].isHebrew) {
        int j = i;
        while (j < words.length && words[j].length == 1 && !words[j].isHebrew && j - i < 6) {
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

class _Span {
  final String text;
  final bool isBold;
  final bool isUnderline;
  final double? fontSize;
  final TextAlign alignment;
  final bool isItalic;
  final bool? isParagraphRtl;
  final Color? highlight;
  final Color? textColor;

  const _Span(
    this.text, {
    this.isBold = false,
    this.isUnderline = false,
    this.fontSize,
    this.alignment = TextAlign.center,
    this.isItalic = false,
    this.isParagraphRtl,
    this.highlight,
    this.textColor,
  });

  _Span copyWith({
    String? text,
    bool? isBold,
    bool? isUnderline,
    double? fontSize,
    TextAlign? alignment,
    bool? isItalic,
    bool? isParagraphRtl,
    Color? highlight,
    Color? textColor,
  }) {
    return _Span(
      text ?? this.text,
      isBold: isBold ?? this.isBold,
      isUnderline: isUnderline ?? this.isUnderline,
      fontSize: fontSize ?? this.fontSize,
      alignment: alignment ?? this.alignment,
      isItalic: isItalic ?? this.isItalic,
      isParagraphRtl: isParagraphRtl ?? this.isParagraphRtl,
      highlight: highlight ?? this.highlight,
      textColor: textColor ?? this.textColor,
    );
  }
}
