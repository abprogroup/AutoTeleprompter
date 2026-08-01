part of 'word_aligner.dart';

/// Walks forward from an already-confirmed match, consuming as many more
/// consecutive already-heard words as keep matching consecutive script
/// words - so a burst the user already said in one breath (e.g. "a real
/// name" right after "script") gets consumed in a single step instead of
/// throttling to one confirmed word per STT round-trip. [anchorTranscriptPos]
/// is the transcript index of [candidateIndex]'s own match.
int _extendConsecutiveRun({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int anchorTranscriptPos,
  required int candidateIndex,
  required bool strictBulletMode,
  int maxExtension = 6,
}) {
  var extendedIndex = candidateIndex;
  var transcriptPos = anchorTranscriptPos + 1;
  var scriptPos = candidateIndex + 1;
  var extensions = 0;
  while (transcriptPos < transcriptWords.length &&
      scriptPos < script.length &&
      extensions < maxExtension) {
    final word = script[scriptPos];
    if (word.isNewline || _isUnspeakable(word) || word.isOptionalCue) {
      scriptPos++;
      continue;
    }
    final threshold = strictBulletMode
        ? WordAligner._strictPhraseThreshold
        : (word.isRtl ? 0.45 : 0.55);
    final sim =
        _wordSimilarity(transcriptWords[transcriptPos], word.normalized, word.isRtl);
    if (sim < threshold) break;
    extendedIndex = scriptPos;
    transcriptPos++;
    scriptPos++;
    extensions++;
  }
  return extendedIndex;
}

/// Same as [_extendConsecutiveRun], but for callers (like STEP 1's
/// next-word check) that only know [candidateIndex] matched *somewhere* in
/// the transcript, not exactly where - finds the most recent occurrence
/// first, then extends from there.
int _extendFromLatestMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int candidateIndex,
  required bool strictBulletMode,
  int maxExtension = 6,
}) {
  if (candidateIndex >= script.length) return candidateIndex;
  final anchorWord = script[candidateIndex];
  final anchorThreshold = strictBulletMode
      ? WordAligner._strictPhraseThreshold
      : (anchorWord.isRtl ? 0.45 : 0.55);
  var anchorPos = -1;
  for (var i = transcriptWords.length - 1; i >= 0; i--) {
    final sim =
        _wordSimilarity(transcriptWords[i], anchorWord.normalized, anchorWord.isRtl);
    if (sim >= anchorThreshold) {
      anchorPos = i;
      break;
    }
  }
  if (anchorPos < 0) return candidateIndex;
  return _extendConsecutiveRun(
    script: script,
    transcriptWords: transcriptWords,
    anchorTranscriptPos: anchorPos,
    candidateIndex: candidateIndex,
    strictBulletMode: strictBulletMode,
    maxExtension: maxExtension,
  );
}

/// The script indices from [start] to [end] inclusive, skipping newlines
/// and unspeakable tokens - used to build evidenceWords/matchedScriptIndices
/// for an extended consecutive-run match.
List<int> _speakableRunIndices(List<ScriptWord> script, int start, int end) {
  final indices = <int>[];
  for (var i = start; i <= end; i++) {
    if (i < 0 || i >= script.length) continue;
    if (script[i].isNewline || _isUnspeakable(script[i])) continue;
    indices.add(i);
  }
  return indices;
}

AlignmentResult? _confirmedTailBridgeMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int lastConfirmedIndex,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length < 2 ||
      lastConfirmedIndex < 0 ||
      lastConfirmedIndex >= script.length) {
    return null;
  }
  final anchor = script[lastConfirmedIndex];
  if (anchor.isNewline || _isUnspeakable(anchor) || anchor.isOptionalCue) {
    return null;
  }

  final localWords = _requiredSpeakableWords(script, lastConfirmedIndex, 4);
  if (localWords.length < 2 || localWords.first.index != lastConfirmedIndex) {
    return null;
  }
  final longest = [
    4,
    transcriptWords.length,
    localWords.length,
  ].reduce((a, b) => a < b ? a : b);

  for (var phraseLen = longest; phraseLen >= 2; phraseLen--) {
    final spokenPhrase = transcriptWords.take(phraseLen).toList();
    var score = 0.0;
    var matched = true;
    for (var i = 0; i < phraseLen; i++) {
      final word = localWords[i];
      final threshold = strictBulletMode
          ? WordAligner._strictPhraseThreshold
          : (word.isRtl ? 0.70 : 0.82);
      final sim = _wordSimilarity(spokenPhrase[i], word.normalized, word.isRtl);
      if (sim < threshold) {
        matched = false;
        break;
      }
      score += sim;
    }
    if (!matched) continue;
    final average = score / phraseLen;
    final target = localWords[phraseLen - 1].index;
    if (target <= lastConfirmedIndex) continue;
    return AlignmentResult(
      target,
      average,
      'CONFIRMED_TAIL_BRIDGE@$lastConfirmedIndex: words=$phraseLen end=$target score=${average.toStringAsFixed(2)}',
      SttAlignmentDecision.advance,
      SttAlignmentKind.confirmedTailBridge,
      SttThresholdFamily.safetyRecovery,
      [for (var i = lastConfirmedIndex; i <= target; i++) i],
      localWords
          .take(phraseLen)
          .skip(1)
          .map((word) => word.normalized)
          .toList(growable: false),
      lastConfirmedIndex,
      target,
    );
  }

  return null;
}

AlignmentResult? _confirmedTailNextWordMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int lastConfirmedIndex,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length < 2 ||
      lastConfirmedIndex < 0 ||
      lastConfirmedIndex >= script.length ||
      searchStart >= script.length) {
    return null;
  }
  final anchor = script[lastConfirmedIndex];
  final next = script[searchStart];
  if (anchor.isNewline ||
      next.isNewline ||
      _isUnspeakable(anchor) ||
      _isUnspeakable(next) ||
      anchor.isOptionalCue) {
    return null;
  }

  final first =
      (transcriptWords.length - 8).clamp(0, transcriptWords.length - 1).toInt();
  for (var i = transcriptWords.length - 2; i >= first; i--) {
    final anchorScore =
        _wordSimilarity(transcriptWords[i], anchor.normalized, anchor.isRtl);
    final nextScore = _wordSimilarity(
      transcriptWords[i + 1],
      next.normalized,
      next.isRtl,
    );
    final anchorThreshold = strictBulletMode
        ? WordAligner._strictPhraseThreshold
        : (anchor.isRtl ? 0.70 : 0.82);
    final nextThreshold = strictBulletMode
        ? WordAligner._strictPhraseThreshold
        : (next.isRtl ? 0.70 : 0.82);
    if (anchorScore < anchorThreshold || nextScore < nextThreshold) continue;
    final confidence = (anchorScore + nextScore) / 2;
    final extendedIndex = _extendConsecutiveRun(
      script: script,
      transcriptWords: transcriptWords,
      anchorTranscriptPos: i + 1,
      candidateIndex: searchStart,
      strictBulletMode: strictBulletMode,
    );
    final matched = _speakableRunIndices(script, searchStart, extendedIndex);
    return AlignmentResult(
      extendedIndex,
      confidence,
      'CONFIRMED_TAIL_NEXT@$lastConfirmedIndex: end=$extendedIndex '
      'score=${confidence.toStringAsFixed(2)}'
      '${extendedIndex > searchStart ? ' streak=${matched.length}' : ''}',
      SttAlignmentDecision.advance,
      SttAlignmentKind.nextWord,
      SttThresholdFamily.safetyRecovery,
      [lastConfirmedIndex, ...matched],
      matched.map((idx) => script[idx].normalized).toList(growable: false),
      lastConfirmedIndex,
      extendedIndex,
    );
  }

  return null;
}

AlignmentResult? _properNameRunBridgeMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int lastConfirmedIndex,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length < 2 || searchStart >= script.length) return null;
  final nameRun = _localProperNamePrefix(script, searchStart);
  if (nameRun.length < 2 || !_endsSentence(nameRun.last.raw)) return null;
  final bodyStart =
      WordAligner.nextRequiredSpeakableIndex(script, nameRun.last.index + 1);
  if (bodyStart >= script.length) return null;
  final bodyWords = _requiredSpeakableWords(script, bodyStart, 3);
  if (bodyWords.length < 2) return null;

  for (var transcriptStart = 0;
      transcriptStart <= transcriptWords.length - 2 &&
          transcriptStart <= nameRun.length + 3;
      transcriptStart++) {
    final available = transcriptWords.length - transcriptStart;
    final longest =
        [3, available, bodyWords.length].reduce((a, b) => a < b ? a : b);
    for (var phraseLen = longest; phraseLen >= 2; phraseLen--) {
      var score = 0.0;
      var matched = true;
      for (var i = 0; i < phraseLen; i++) {
        final word = bodyWords[i];
        final threshold = strictBulletMode
            ? WordAligner._strictPhraseThreshold
            : (word.isRtl ? 0.70 : 0.82);
        final sim = _wordSimilarity(
          transcriptWords[transcriptStart + i],
          word.normalized,
          word.isRtl,
        );
        if (sim < threshold) {
          matched = false;
          break;
        }
        score += sim;
      }
      if (!matched) continue;
      final average = score / phraseLen;
      final target = bodyWords[phraseLen - 1].index;
      final jump = target - lastConfirmedIndex;
      if (jump <= 0 || jump > nameRun.length + phraseLen + 1) continue;
      return AlignmentResult(
        target,
        average,
        'NAME_RUN_BODY_BRIDGE@$searchStart: names=${nameRun.length} transcript=$transcriptStart words=$phraseLen end=$target score=${average.toStringAsFixed(2)}',
        SttAlignmentDecision.advance,
        SttAlignmentKind.nameRunBodyBridge,
        SttThresholdFamily.safetyRecovery,
        [for (var i = bodyStart; i <= target; i++) i],
        bodyWords
            .take(phraseLen)
            .map((word) => word.normalized)
            .toList(growable: false),
        bodyStart,
        target,
      );
    }
  }

  return null;
}

List<ScriptWord> _localProperNamePrefix(
  List<ScriptWord> script,
  int searchStart,
) {
  final names = <ScriptWord>[];
  for (var cursor = searchStart;
      cursor < script.length && names.length < 4;
      cursor++) {
    final word = script[cursor];
    if (word.isNewline || _isUnspeakable(word) || word.isOptionalCue) break;
    if (names.isNotEmpty && _endsSentence(script[cursor - 1].raw)) break;
    if (_isNameBridgeTitle(word.normalized)) break;
    if (!_isLikelyProperNameWord(word)) break;
    names.add(word);
  }
  return names;
}

bool _isNameBridgeTitle(String normalized) {
  final cleaned = normalized.replaceAll(RegExp(r"[^a-z]"), '');
  const titles = {'mr', 'mrs', 'ms', 'dr', 'prof', 'mayor'};
  return titles.contains(cleaned);
}

bool _endsSentence(String raw) => RegExp(r'''[.!?]["')\]]*$''').hasMatch(raw);

AlignmentResult? _pendingSingleWordContinuation({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int pendingTargetIndex,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length != 1 ||
      searchStart >= script.length ||
      script[searchStart].isNewline ||
      _isUnspeakable(script[searchStart])) {
    return null;
  }
  final word = script[searchStart];
  final threshold = strictBulletMode
      ? WordAligner._strictPhraseThreshold
      : (word.isRtl ? 0.70 : 0.82);
  final sim =
      _wordSimilarity(transcriptWords.single, word.normalized, word.isRtl);
  if (sim < threshold) return null;
  return AlignmentResult(
    searchStart,
    sim,
    'CONTINUED_START_WORD@$searchStart: "${transcriptWords.single}" ~ '
    '"${word.normalized}" = ${sim.toStringAsFixed(2)}',
    SttAlignmentDecision.advance,
    SttAlignmentKind.confirmedTailBridge,
    SttThresholdFamily.startAdvance,
    [searchStart],
    [word.normalized],
    searchStart,
    searchStart,
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
