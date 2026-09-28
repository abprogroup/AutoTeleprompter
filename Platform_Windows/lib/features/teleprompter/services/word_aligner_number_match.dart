part of 'word_aligner.dart';

_NumberAwareOutcome? _numberAwareMatch({
  required List<ScriptWord> script,
  required String transcript,
  required int lastConfirmedIndex,
  required int scanStart,
  required int scanEnd,
  required bool strictBulletMode,
  required SttRecognitionPolicy policy,
  required bool visibleSkipEnabled,
  int? visibleSkipStartIndex,
}) {
  if (scanStart >= scanEnd || transcript.trim().isEmpty) return null;

  final transcriptSurfaces = SpokenNumberNormalizer.surfaceTokens(transcript);
  final hasTailNumericIntent = SpokenNumberNormalizer.hasTailNumericIntent(
    transcriptSurfaces,
  );
  final transcriptSpans = SpokenNumberNormalizer.scan(
    transcriptSurfaces,
    allowYearPairs: true,
  );
  final scriptSpans = _scriptNumberSpans(script, scanStart, scanEnd);
  if (scriptSpans.isEmpty) return null;
  if (transcriptSpans.isEmpty) {
    return hasTailNumericIntent
        ? const _NumberAwareOutcome(blocksGenericFallback: true)
        : null;
  }

  final transcriptUnits = _transcriptNumberUnits(
    transcriptSurfaces,
    transcriptSpans,
  );
  final scriptUnits = _scriptNumberUnits(
    script,
    scanStart,
    scanEnd,
    scriptSpans,
  );
  if (transcriptUnits.isEmpty || scriptUnits.isEmpty) return null;

  _NumberCandidate? best;
  final yearPairCandidates = <_NumberCandidate>[];
  final mismatchCandidates = <_NumberMismatchCandidate>[];
  var hadEquivalentAnchor = false;
  var hadMismatchedTailContext = false;
  for (
    var transcriptIndex = 0;
    transcriptIndex < transcriptUnits.length;
    transcriptIndex++
  ) {
    final heardNumber = transcriptUnits[transcriptIndex].number;
    if (heardNumber == null) continue;
    for (var scriptIndex = 0; scriptIndex < scriptUnits.length; scriptIndex++) {
      final writtenNumber = scriptUnits[scriptIndex].number;
      if (writtenNumber == null) continue;
      final scriptNumberIndex = scriptUnits[scriptIndex].start;
      final heardYearPair = heardNumber.kind == SpokenNumberKind.yearPair;
      final yearCueIndex =
          heardYearPair ? _scriptYearCueIndex(script, scriptNumberIndex) : null;
      if (heardYearPair &&
          (writtenNumber.integer < 1000 ||
              writtenNumber.integer > 2999 ||
              yearCueIndex == null)) {
        continue;
      }
      if (!heardNumber.equivalentTo(writtenNumber)) {
        final mismatch = _growNumberMismatchCandidate(
          transcriptUnits: transcriptUnits,
          scriptUnits: scriptUnits,
          transcriptAnchor: transcriptIndex,
          scriptAnchor: scriptIndex,
          strictBulletMode: strictBulletMode,
        );
        if ((visibleSkipStartIndex == null ||
                scriptNumberIndex >= visibleSkipStartIndex) &&
            (mismatch?.reachesTranscriptTail ?? false)) {
          hadMismatchedTailContext = true;
        }
        if (strictBulletMode ||
            transcriptSpans.length != 1 ||
            mismatch == null ||
            !mismatch.reachesTranscriptTail ||
            mismatch.prefixLexicalMatches == 0 ||
            policy.safetyRecovery.smallWords < 1) {
          continue;
        }
        if (heardYearPair &&
            !mismatch.prefixMatchedScriptIndices.contains(yearCueIndex)) {
          continue;
        }

        // A wrong number is never a normal local continuation. Crossing it
        // always needs the same two independent gates: enough trusted visible
        // context overall, plus the configured lexical safety evidence after
        // the number. This keeps near and far candidates equally fail-closed.
        if (!visibleSkipEnabled) continue;
        if (visibleSkipStartIndex != null &&
            mismatch.candidateStartIndex < visibleSkipStartIndex) {
          continue;
        }
        if (mismatch.lexicalAverage < 0.70 ||
            policy.visibleSkip.evidenceScore(mismatch.evidenceWords) < 2) {
          continue;
        }

        final canCrossMismatch =
            mismatch.suffixLexicalMatches > 0 &&
            policy.safetyRecovery.passes(mismatch.suffixEvidence);
        const family = SttThresholdFamily.visibleSkip;
        final result =
            canCrossMismatch
                ? mismatch.toRecoveryResult(
                  thresholdFamily: family,
                  heard: heardNumber,
                  written: writtenNumber,
                )
                : mismatch.toPendingResult(
                  thresholdFamily: family,
                  heard: heardNumber,
                  written: writtenNumber,
                );
        if (result.confirmedWordIndex > lastConfirmedIndex) {
          mismatchCandidates.add(mismatch.copyWithResult(result));
        }
        continue;
      }
      final candidate = _growNumberCandidate(
        transcriptUnits: transcriptUnits,
        scriptUnits: scriptUnits,
        transcriptAnchor: transcriptIndex,
        scriptAnchor: scriptIndex,
        strictBulletMode: strictBulletMode,
      );
      if (!candidate.reachesTranscriptTail) continue;
      hadEquivalentAnchor = true;
      final immediate = scriptIndex == 0;
      final targetJump = candidate.targetIndex - lastConfirmedIndex;
      final localJumpLimit =
          immediate
              ? WordAligner.maxLocalNumberAdvance
              : WordAligner._maxSingleJump;
      final far = targetJump > localJumpLimit;
      if (heardYearPair &&
          far &&
          !candidate.matchedScriptIndices.contains(yearCueIndex)) {
        continue;
      }

      // A number by itself is useful only as the immediate continuation. It
      // can never select a repeated/distant value or become a paragraph jump.
      if (candidate.lexicalMatches == 0 && !immediate) continue;
      if (strictBulletMode && candidate.lexicalMatches < 2) continue;
      if (strictBulletMode &&
          (candidate.lexicalAverage < WordAligner._strictPhraseThreshold ||
              !policy.bulletAdvance.passes(candidate.evidenceWords))) {
        continue;
      }
      if (far) {
        if (!visibleSkipEnabled || candidate.lexicalMatches < 2) continue;
        if (visibleSkipStartIndex != null &&
            candidate.candidateStartIndex < visibleSkipStartIndex) {
          continue;
        }
        if (candidate.lexicalAverage < 0.70) continue;
        if (!policy.visibleSkip.passes(candidate.evidenceWords)) continue;
      }
      if (lastConfirmedIndex < 0 &&
          !policy.startAdvance.passes(candidate.lexicalEvidence)) {
        continue;
      }

      final family =
          far
              ? SttThresholdFamily.visibleSkip
              : strictBulletMode
              ? SttThresholdFamily.bulletAdvance
              : lastConfirmedIndex < 0
              ? SttThresholdFamily.startAdvance
              : SttThresholdFamily.safetyRecovery;
      final result = candidate.toAlignmentResult(
        thresholdFamily: family,
        heard: heardNumber,
        written: writtenNumber,
      );

      final completed = candidate.copyWithResult(result);
      if (heardYearPair) {
        yearPairCandidates.add(completed);
      } else if (best == null || candidate.isBetterThan(best)) {
        best = completed;
      }
    }
  }
  if (yearPairCandidates.isNotEmpty) {
    var selected = yearPairCandidates.first;
    for (final candidate in yearPairCandidates.skip(1)) {
      if (candidate.isBetterThan(selected)) selected = candidate;
    }
    final ambiguous =
        selected.result?.thresholdFamily == SttThresholdFamily.visibleSkip &&
        yearPairCandidates.any(
          (candidate) =>
              candidate.numericScriptStart != selected.numericScriptStart &&
              candidate.hasEquivalentEvidenceQuality(selected),
        );
    if (ambiguous) {
      return const _NumberAwareOutcome(blocksGenericFallback: true);
    }
    if (best == null || selected.isBetterThan(best)) best = selected;
  }
  if (best?.result != null) {
    return _NumberAwareOutcome(result: best!.result);
  }
  if (mismatchCandidates.isNotEmpty) {
    var selected = mismatchCandidates.first;
    for (final candidate in mismatchCandidates.skip(1)) {
      if (candidate.isBetterThan(selected)) selected = candidate;
    }
    final ambiguous = mismatchCandidates.any(
      (candidate) =>
          candidate.numericScriptStart != selected.numericScriptStart &&
          candidate.hasEquivalentEvidenceQuality(selected),
    );
    if (!ambiguous && selected.result != null) {
      return _NumberAwareOutcome(result: selected.result);
    }
  }
  return hadEquivalentAnchor || hadMismatchedTailContext || hasTailNumericIntent
      ? const _NumberAwareOutcome(blocksGenericFallback: true)
      : null;
}

class _NumberAwareOutcome {
  final AlignmentResult? result;
  final bool blocksGenericFallback;

  const _NumberAwareOutcome({this.result, this.blocksGenericFallback = false});
}

int? _scriptYearCueIndex(List<ScriptWord> script, int numberIndex) {
  if (numberIndex <= 0 || numberIndex > script.length) return null;
  final cue = script[numberIndex - 1];
  if (cue.isNewline || cue.isOptionalCue) return null;
  const yearCues = {'בשנת', 'שנת', 'לשנת', 'משנת', 'בשנה', 'שנה', 'year'};
  return yearCues.contains(cue.normalized) ? numberIndex - 1 : null;
}

List<_ScriptNumberSpan> _scriptNumberSpans(
  List<ScriptWord> script,
  int rawStart,
  int rawEnd,
) {
  final start = rawStart.clamp(0, script.length).toInt();
  final end = rawEnd.clamp(start, script.length).toInt();
  if (start >= end) return const [];
  final surfaces = [for (var i = start; i < end; i++) script[i].raw];
  final parsed = SpokenNumberNormalizer.scan(surfaces);
  final spans = <_ScriptNumberSpan>[];
  for (final span in parsed) {
    final sourceStart = start + span.start;
    final sourceEnd = start + span.endExclusive;
    if (sourceEnd - sourceStart == 1 &&
        _isNumberedHeadingMarker(script, sourceStart)) {
      continue;
    }
    var valid = true;
    for (var i = sourceStart; i < sourceEnd; i++) {
      if (script[i].isNewline || script[i].isOptionalCue) {
        valid = false;
        break;
      }
    }
    if (!valid) continue;
    spans.add(
      _ScriptNumberSpan(
        start: sourceStart,
        endExclusive: sourceEnd,
        value: span.value,
      ),
    );
  }
  return spans;
}

bool _isNumberedHeadingMarker(List<ScriptWord> script, int index) {
  if (index < 0 || index >= script.length) return false;
  final visible =
      script[index].raw.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '').trim();
  if (RegExp(r'^(?:\(\d{1,3}\)[\.:]?|\d{1,3}\)\.)$').hasMatch(visible)) {
    return true;
  }
  final lineLeading = index == 0 || script[index - 1].isNewline;
  if (!lineLeading) return false;
  if (RegExp(r'^\d{1,3}[\.\):]$').hasMatch(visible)) {
    return true;
  }
  if (!RegExp(r'^\d{1,3}$').hasMatch(visible) || index + 1 >= script.length) {
    return false;
  }
  final next =
      script[index + 1].raw.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '').trim();
  return RegExp(r'^[-\u05BE\u2010-\u2015:]+$').hasMatch(next);
}

List<_NumberAlignmentUnit> _transcriptNumberUnits(
  List<String> surfaces,
  List<SpokenNumberSpan> spans,
) {
  final byStart = {for (final span in spans) span.start: span};
  final units = <_NumberAlignmentUnit>[];
  var cursor = 0;
  while (cursor < surfaces.length) {
    final span = byStart[cursor];
    if (span != null) {
      units.add(
        _NumberAlignmentUnit.number(
          number: span.value,
          start: span.start,
          endExclusive: span.endExclusive,
        ),
      );
      if (_hasHardBoundaryAfter(surfaces[span.endExclusive - 1])) {
        units.add(_NumberAlignmentUnit.boundary(span.endExclusive));
      }
      cursor = span.endExclusive;
      continue;
    }
    final normalized = surfaces[cursor].normalizeForMatching();
    if (normalized.isNotEmpty) {
      units.add(
        _NumberAlignmentUnit.word(
          word: normalized,
          start: cursor,
          endExclusive: cursor + 1,
          isRtl: normalized.isHebrew,
        ),
      );
      if (_hasHardBoundaryAfter(surfaces[cursor])) {
        units.add(_NumberAlignmentUnit.boundary(cursor + 1));
      }
    }
    cursor++;
  }
  return units;
}

List<_NumberAlignmentUnit> _scriptNumberUnits(
  List<ScriptWord> script,
  int start,
  int end,
  List<_ScriptNumberSpan> spans,
) {
  final byStart = {for (final span in spans) span.start: span};
  final units = <_NumberAlignmentUnit>[];
  var cursor = start;
  while (cursor < end) {
    final span = byStart[cursor];
    if (span != null) {
      units.add(
        _NumberAlignmentUnit.number(
          number: span.value,
          start: span.start,
          endExclusive: span.endExclusive,
        ),
      );
      if (_hasHardBoundaryAfter(script[span.endExclusive - 1].raw)) {
        units.add(_NumberAlignmentUnit.boundary(span.endExclusive));
      }
      cursor = span.endExclusive;
      continue;
    }
    final word = script[cursor];
    if (word.isNewline || word.isOptionalCue) {
      if (units.isEmpty || !units.last.isBoundary) {
        units.add(_NumberAlignmentUnit.boundary(cursor));
      }
    } else if (!_isUnspeakable(word)) {
      units.add(
        _NumberAlignmentUnit.word(
          word: word.normalized,
          start: cursor,
          endExclusive: cursor + 1,
          isRtl: word.isRtl,
        ),
      );
      if (_hasHardBoundaryAfter(word.raw)) {
        units.add(_NumberAlignmentUnit.boundary(cursor + 1));
      }
    } else if (_hasStructuredNumericPunctuation(word.raw)) {
      if (units.isEmpty || !units.last.isBoundary) {
        units.add(_NumberAlignmentUnit.boundary(cursor));
      }
    }
    cursor++;
  }
  return units;
}

bool _hasHardBoundaryAfter(String raw) {
  final visible = raw.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '').trim();
  return RegExp(r'[.!?;:]$').hasMatch(visible);
}

bool _hasStructuredNumericPunctuation(String raw) {
  final visible = raw.replaceAll(RegExp(r'\[[^\]]+\]|\*\*'), '').trim();
  return RegExp(r'\d[\.,:/\-\u05BE\u2010-\u2015\u2212]\d').hasMatch(visible) ||
      RegExp(r'^[+\-\u2010-\u2015\u2212]\d').hasMatch(visible) ||
      RegExp(r'[$₪%]').hasMatch(visible);
}

_NumberCandidate _growNumberCandidate({
  required List<_NumberAlignmentUnit> transcriptUnits,
  required List<_NumberAlignmentUnit> scriptUnits,
  required int transcriptAnchor,
  required int scriptAnchor,
  required bool strictBulletMode,
}) {
  var transcriptStart = transcriptAnchor;
  var transcriptEnd = transcriptAnchor;
  var scriptStart = scriptAnchor;
  var scriptEnd = scriptAnchor;
  var lexicalMatches = 0;
  var similarityTotal = 1.0;
  var lexicalSimilarityTotal = 0.0;
  var extensionCount = 0;

  var ti = transcriptAnchor - 1;
  var si = scriptAnchor - 1;
  while (ti >= 0 &&
      si >= 0 &&
      extensionCount < SpokenNumberNormalizer.maxSpanTokens) {
    final score = _numberUnitSimilarity(
      transcriptUnits[ti],
      scriptUnits[si],
      strictBulletMode: strictBulletMode,
    );
    if (score == null) break;
    transcriptStart = ti;
    scriptStart = si;
    if (transcriptUnits[ti].number == null) {
      lexicalMatches++;
      lexicalSimilarityTotal += score;
    }
    similarityTotal += score;
    extensionCount++;
    ti--;
    si--;
  }

  ti = transcriptAnchor + 1;
  si = scriptAnchor + 1;
  extensionCount = 0;
  while (ti < transcriptUnits.length &&
      si < scriptUnits.length &&
      extensionCount < SpokenNumberNormalizer.maxSpanTokens) {
    final score = _numberUnitSimilarity(
      transcriptUnits[ti],
      scriptUnits[si],
      strictBulletMode: strictBulletMode,
    );
    if (score == null) break;
    transcriptEnd = ti;
    scriptEnd = si;
    if (transcriptUnits[ti].number == null) {
      lexicalMatches++;
      lexicalSimilarityTotal += score;
    }
    similarityTotal += score;
    extensionCount++;
    ti++;
    si++;
  }

  final evidence = <String>[];
  final lexicalEvidence = <String>[];
  for (var i = transcriptStart; i <= transcriptEnd; i++) {
    final unit = transcriptUnits[i];
    if (unit.number != null) {
      evidence.add('num');
    } else if (unit.word != null) {
      evidence.add(unit.word!);
      lexicalEvidence.add(unit.word!);
    }
  }
  if (!evidence.contains('num')) evidence.add('num');

  final matchedIndices = <int>[];
  for (var i = scriptStart; i <= scriptEnd; i++) {
    final unit = scriptUnits[i];
    for (var index = unit.start; index < unit.endExclusive; index++) {
      matchedIndices.add(index);
    }
  }
  final unitCount = scriptEnd - scriptStart + 1;
  return _NumberCandidate(
    targetIndex: scriptUnits[scriptEnd].endExclusive - 1,
    candidateStartIndex: scriptUnits[scriptStart].start,
    candidateEndIndex: scriptUnits[scriptEnd].endExclusive - 1,
    numericScriptStart: scriptUnits[scriptAnchor].start,
    transcriptEndUnit: transcriptEnd,
    transcriptLastMeaningfulUnit: _lastMeaningfulUnitIndex(transcriptUnits),
    lexicalMatches: lexicalMatches,
    lexicalAverage:
        lexicalMatches == 0 ? 0.0 : lexicalSimilarityTotal / lexicalMatches,
    confidence: similarityTotal / unitCount,
    matchedScriptIndices: matchedIndices,
    evidenceWords: evidence,
    lexicalEvidence: lexicalEvidence,
  );
}

double? _numberUnitSimilarity(
  _NumberAlignmentUnit heard,
  _NumberAlignmentUnit written, {
  required bool strictBulletMode,
}) {
  if (heard.isBoundary || written.isBoundary) return null;
  if (heard.number != null || written.number != null) {
    if (heard.number == null || written.number == null) return null;
    return heard.number!.equivalentTo(written.number!) ? 1.0 : null;
  }
  final heardWord = heard.word;
  final writtenWord = written.word;
  if (heardWord == null || writtenWord == null) return null;
  final score = _wordSimilarity(heardWord, writtenWord, written.isRtl);
  final threshold =
      strictBulletMode
          ? WordAligner._strictPhraseThreshold
          : written.isRtl
          ? WordAligner._hebrewMatchThreshold
          : WordAligner._matchThreshold;
  return score >= threshold ? score : null;
}

int _lastMeaningfulUnitIndex(List<_NumberAlignmentUnit> units) {
  for (var i = units.length - 1; i >= 0; i--) {
    if (!units[i].isBoundary) return i;
  }
  return -1;
}

class _ScriptNumberSpan {
  final int start;
  final int endExclusive;
  final SpokenNumberValue value;

  const _ScriptNumberSpan({
    required this.start,
    required this.endExclusive,
    required this.value,
  });
}

class _NumberAlignmentUnit {
  final String? word;
  final SpokenNumberValue? number;
  final int start;
  final int endExclusive;
  final bool isRtl;
  final bool isBoundary;

  const _NumberAlignmentUnit._({
    required this.word,
    required this.number,
    required this.start,
    required this.endExclusive,
    required this.isRtl,
    required this.isBoundary,
  });

  factory _NumberAlignmentUnit.word({
    required String word,
    required int start,
    required int endExclusive,
    required bool isRtl,
  }) => _NumberAlignmentUnit._(
    word: word,
    number: null,
    start: start,
    endExclusive: endExclusive,
    isRtl: isRtl,
    isBoundary: false,
  );

  factory _NumberAlignmentUnit.number({
    required SpokenNumberValue number,
    required int start,
    required int endExclusive,
  }) => _NumberAlignmentUnit._(
    word: null,
    number: number,
    start: start,
    endExclusive: endExclusive,
    isRtl: false,
    isBoundary: false,
  );

  factory _NumberAlignmentUnit.boundary(int offset) => _NumberAlignmentUnit._(
    word: null,
    number: null,
    start: offset,
    endExclusive: offset,
    isRtl: false,
    isBoundary: true,
  );
}

class _NumberCandidate {
  final int targetIndex;
  final int candidateStartIndex;
  final int candidateEndIndex;
  final int numericScriptStart;
  final int transcriptEndUnit;
  final int transcriptLastMeaningfulUnit;
  final int lexicalMatches;
  final double lexicalAverage;
  final double confidence;
  final List<int> matchedScriptIndices;
  final List<String> evidenceWords;
  final List<String> lexicalEvidence;
  final AlignmentResult? result;

  const _NumberCandidate({
    required this.targetIndex,
    required this.candidateStartIndex,
    required this.candidateEndIndex,
    required this.numericScriptStart,
    required this.transcriptEndUnit,
    required this.transcriptLastMeaningfulUnit,
    required this.lexicalMatches,
    required this.lexicalAverage,
    required this.confidence,
    required this.matchedScriptIndices,
    required this.evidenceWords,
    required this.lexicalEvidence,
    this.result,
  });

  bool get reachesTranscriptTail =>
      transcriptEndUnit == transcriptLastMeaningfulUnit;

  bool isBetterThan(_NumberCandidate other) {
    if (lexicalMatches != other.lexicalMatches) {
      return lexicalMatches > other.lexicalMatches;
    }
    if (numericScriptStart != other.numericScriptStart) {
      return numericScriptStart < other.numericScriptStart;
    }
    if (targetIndex != other.targetIndex) {
      return targetIndex > other.targetIndex;
    }
    return confidence > other.confidence;
  }

  bool hasEquivalentEvidenceQuality(_NumberCandidate other) =>
      lexicalMatches == other.lexicalMatches &&
      (lexicalAverage - other.lexicalAverage).abs() < 0.0001 &&
      (confidence - other.confidence).abs() < 0.0001;

  AlignmentResult toAlignmentResult({
    required SttThresholdFamily thresholdFamily,
    required SpokenNumberValue heard,
    required SpokenNumberValue written,
  }) => AlignmentResult(
    targetIndex,
    confidence,
    'NUMBER_MATCH: heard=${heard.debugLabel} '
    'script=${written.debugLabel} lexical=$lexicalMatches '
    'range=$candidateStartIndex-$candidateEndIndex',
    SttAlignmentDecision.advance,
    SttAlignmentKind.numberPhrase,
    thresholdFamily,
    matchedScriptIndices,
    evidenceWords,
    candidateStartIndex,
    candidateEndIndex,
  );

  _NumberCandidate copyWithResult(AlignmentResult value) => _NumberCandidate(
    targetIndex: targetIndex,
    candidateStartIndex: candidateStartIndex,
    candidateEndIndex: candidateEndIndex,
    numericScriptStart: numericScriptStart,
    transcriptEndUnit: transcriptEndUnit,
    transcriptLastMeaningfulUnit: transcriptLastMeaningfulUnit,
    lexicalMatches: lexicalMatches,
    lexicalAverage: lexicalAverage,
    confidence: confidence,
    matchedScriptIndices: matchedScriptIndices,
    evidenceWords: evidenceWords,
    lexicalEvidence: lexicalEvidence,
    result: value,
  );
}
