part of 'word_aligner.dart';

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
    return AlignmentResult(
      searchStart,
      confidence,
      'CONFIRMED_TAIL_NEXT@$lastConfirmedIndex: end=$searchStart '
      'score=${confidence.toStringAsFixed(2)}',
      SttAlignmentDecision.advance,
      SttAlignmentKind.nextWord,
      SttThresholdFamily.safetyRecovery,
      [lastConfirmedIndex, searchStart],
      [next.normalized],
      lastConfirmedIndex,
      searchStart,
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
