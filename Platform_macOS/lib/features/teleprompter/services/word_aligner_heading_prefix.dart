part of 'word_aligner.dart';

AlignmentResult? _headingPrefixSkipMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int searchStart,
  required int lastConfirmedIndex,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length < 2) return null;
  final bodyStart =
      _headingPrefixBodyStart(script, searchStart, lastConfirmedIndex);
  if (bodyStart == null) return null;

  final bodyWords = _requiredSpeakableWords(script, bodyStart, 3);
  final longest = [
    3,
    transcriptWords.length,
    bodyWords.length,
  ].reduce((a, b) => a < b ? a : b);
  for (var phraseLen = longest; phraseLen >= 2; phraseLen--) {
    final spokenPhrase = transcriptWords.take(phraseLen).toList();
    if (!_hasUsefulPhraseWords(spokenPhrase, 2)) continue;
    var score = 0.0;
    var matched = true;
    for (var i = 0; i < phraseLen; i++) {
      final bodyWord = bodyWords[i];
      final threshold = strictBulletMode
          ? WordAligner._strictPhraseThreshold
          : (bodyWord.isRtl ? 0.70 : 0.82);
      final sim =
          _wordSimilarity(spokenPhrase[i], bodyWord.normalized, bodyWord.isRtl);
      if (sim < threshold) {
        matched = false;
        break;
      }
      score += sim;
    }
    if (!matched) continue;
    final average = score / phraseLen;
    final target = bodyWords[phraseLen - 1].index;
    return AlignmentResult(
      target,
      average,
      'HEADING_PREFIX_SKIP@$searchStart: body=$bodyStart words=$phraseLen end=$target score=${average.toStringAsFixed(2)}',
      SttAlignmentDecision.advance,
      SttAlignmentKind.headingPrefixSkip,
      SttThresholdFamily.startAdvance,
      [for (var i = bodyStart; i <= target; i++) i],
      bodyWords
          .take(phraseLen)
          .map((word) => word.normalized)
          .toList(growable: false),
      bodyStart,
      target,
    );
  }

  final bodyBridge = _headingPrefixAnchoredBodyBridgeMatch(
    script: script,
    transcriptWords: transcriptWords,
    bodyStart: bodyStart,
    strictBulletMode: strictBulletMode,
  );
  if (bodyBridge != null) return bodyBridge;

  return null;
}

AlignmentResult? _headingPrefixAnchoredBodyBridgeMatch({
  required List<ScriptWord> script,
  required List<String> transcriptWords,
  required int bodyStart,
  required bool strictBulletMode,
}) {
  if (transcriptWords.length < 3) return null;
  final bodyWords = _requiredSpeakableWords(script, bodyStart, 10);
  if (bodyWords.length < 4) return null;

  final firstBody = bodyWords.first;
  final threshold = strictBulletMode
      ? WordAligner._strictPhraseThreshold
      : (firstBody.isRtl ? 0.70 : 0.82);
  var anchorTranscriptIndex = -1;
  for (var i = 0; i < transcriptWords.length && i < 2; i++) {
    final sim = _wordSimilarity(
        transcriptWords[i], firstBody.normalized, firstBody.isRtl);
    if (sim >= threshold) {
      anchorTranscriptIndex = i;
      break;
    }
  }
  if (anchorTranscriptIndex < 0) return null;

  for (var phraseLen = 3; phraseLen >= 2; phraseLen--) {
    for (var bodyOffset = 1;
        bodyOffset <= 6 && bodyOffset + phraseLen <= bodyWords.length;
        bodyOffset++) {
      final phraseWords = bodyWords.sublist(bodyOffset, bodyOffset + phraseLen);
      final scriptGap = bodyWords.sublist(1, bodyOffset);
      if (!_headingBridgeCanSkipGap(scriptGap)) continue;

      for (var transcriptStart = anchorTranscriptIndex + 1;
          transcriptStart + phraseLen <= transcriptWords.length &&
              transcriptStart <= anchorTranscriptIndex + 5;
          transcriptStart++) {
        var score = 0.0;
        var matched = true;
        for (var i = 0; i < phraseLen; i++) {
          final phraseWord = phraseWords[i];
          final phraseThreshold = strictBulletMode
              ? WordAligner._strictPhraseThreshold
              : (phraseWord.isRtl ? 0.70 : 0.82);
          final sim = _wordSimilarity(
            transcriptWords[transcriptStart + i],
            phraseWord.normalized,
            phraseWord.isRtl,
          );
          if (sim < phraseThreshold) {
            matched = false;
            break;
          }
          score += sim;
        }
        if (!matched) continue;

        final target = phraseWords.last.index;
        final average = score / phraseLen;
        return AlignmentResult(
          target,
          average,
          'HEADING_NAME_BODY_BRIDGE@$bodyStart: phrase=$bodyOffset '
          'words=$phraseLen transcript=$transcriptStart end=$target '
          'score=${average.toStringAsFixed(2)}',
          SttAlignmentDecision.advance,
          SttAlignmentKind.headingPrefixSkip,
          SttThresholdFamily.startAdvance,
          [firstBody.index, for (final word in phraseWords) word.index],
          [
            firstBody.normalized,
            ...phraseWords.map((word) => word.normalized),
          ],
          bodyStart,
          target,
        );
      }
    }
  }

  return null;
}

int? _headingPrefixBodyStart(
  List<ScriptWord> script,
  int searchStart,
  int lastConfirmedIndex,
) {
  if (_confirmedInsideHeadingPrefixBeforeBody(
    script,
    searchStart,
    lastConfirmedIndex,
  )) {
    return searchStart;
  }
  if (!_hasRecentHeadingMarker(script, lastConfirmedIndex, searchStart)) {
    return null;
  }
  final prefix = <String>[];
  var cursor = searchStart;
  while (cursor < script.length && prefix.length < 4) {
    final word = script[cursor];
    if (word.isNewline) break;
    if (_isUnspeakable(word) || word.isOptionalCue) {
      cursor++;
      continue;
    }
    if (!_isHeadingPrefixWord(word.normalized)) break;
    prefix.add(word.normalized);
    cursor++;
  }
  if (!_isValidHeadingPrefix(prefix)) return null;
  final bodyStart = WordAligner.nextRequiredSpeakableIndex(script, cursor);
  return bodyStart < script.length ? bodyStart : null;
}

bool _confirmedInsideHeadingPrefixBeforeBody(
  List<ScriptWord> script,
  int searchStart,
  int lastConfirmedIndex,
) {
  if (lastConfirmedIndex < 0 ||
      lastConfirmedIndex >= script.length ||
      searchStart >= script.length) {
    return false;
  }
  final nextRequired =
      WordAligner.nextRequiredSpeakableIndex(script, lastConfirmedIndex + 1);
  if (nextRequired != searchStart) return false;

  final prefix = <String>[];
  for (var cursor = lastConfirmedIndex;
      cursor >= 0 && prefix.length < 4;
      cursor--) {
    final word = script[cursor];
    if (word.isNewline) return false;
    if (_isUnspeakable(word)) {
      return _isValidHeadingPrefix(prefix.reversed.toList());
    }
    if (!_isHeadingPrefixWord(word.normalized)) return false;
    prefix.add(word.normalized);
  }
  return false;
}

bool _hasRecentHeadingMarker(
  List<ScriptWord> script,
  int lastConfirmedIndex,
  int searchStart,
) {
  final start = lastConfirmedIndex.clamp(0, script.length).toInt();
  final end = searchStart.clamp(0, script.length).toInt();
  for (var i = start; i < end; i++) {
    if (_isUnspeakable(script[i])) return true;
  }
  return false;
}

List<ScriptWord> _requiredSpeakableWords(
  List<ScriptWord> script,
  int startIndex,
  int maxWords,
) {
  final words = <ScriptWord>[];
  var cursor = startIndex;
  while (cursor < script.length && words.length < maxWords) {
    final next = WordAligner.nextRequiredSpeakableIndex(script, cursor);
    if (next >= script.length) break;
    words.add(script[next]);
    cursor = next + 1;
  }
  return words;
}

bool _isHeadingPrefixWord(String normalized) {
  const words = {
    'agenda',
    'closing',
    'intro',
    'introduction',
    'opening',
    'remarks',
    'remark',
    'section',
    'transition',
    'welcome',
  };
  return words.contains(normalized);
}

bool _isValidHeadingPrefix(List<String> prefix) {
  if (prefix.isEmpty) return false;
  if (prefix.length == 1) {
    return const {'agenda', 'intro', 'introduction', 'section', 'transition'}
        .contains(prefix.first);
  }
  final startsRemarkHeading =
      const {'opening', 'closing', 'welcome'}.contains(prefix.first);
  return startsRemarkHeading &&
      (prefix.contains('remarks') || prefix.contains('remark'));
}

bool _headingBridgeCanSkipGap(List<ScriptWord> gap) {
  if (gap.isEmpty || gap.length > 4) return false;
  var properNames = 0;
  for (final word in gap) {
    if (word.isNewline || _isUnspeakable(word) || word.isOptionalCue) {
      continue;
    }
    if (_isNameBridgeTitle(word.normalized)) continue;
    if (!_isLikelyProperNameWord(word)) return false;
    properNames++;
  }
  return properNames > 0;
}
