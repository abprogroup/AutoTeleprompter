part of 'word_aligner.dart';

_NumberMismatchCandidate? _growNumberMismatchCandidate({
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
  var prefixMatches = 0;
  var suffixMatches = 0;
  var similarityTotal = 0.0;

  var transcriptIndex = transcriptAnchor - 1;
  var scriptIndex = scriptAnchor - 1;
  while (transcriptIndex >= 0 && scriptIndex >= 0) {
    final score = _lexicalNumberContextSimilarity(
      transcriptUnits[transcriptIndex],
      scriptUnits[scriptIndex],
      strictBulletMode: strictBulletMode,
    );
    if (score == null) break;
    transcriptStart = transcriptIndex;
    scriptStart = scriptIndex;
    prefixMatches++;
    similarityTotal += score;
    transcriptIndex--;
    scriptIndex--;
  }

  transcriptIndex = transcriptAnchor + 1;
  scriptIndex = scriptAnchor + 1;
  while (transcriptIndex < transcriptUnits.length &&
      scriptIndex < scriptUnits.length) {
    final score = _lexicalNumberContextSimilarity(
      transcriptUnits[transcriptIndex],
      scriptUnits[scriptIndex],
      strictBulletMode: strictBulletMode,
    );
    if (score == null) break;
    transcriptEnd = transcriptIndex;
    scriptEnd = scriptIndex;
    suffixMatches++;
    similarityTotal += score;
    transcriptIndex++;
    scriptIndex++;
  }

  final lexicalMatches = prefixMatches + suffixMatches;
  if (lexicalMatches == 0) return null;

  final prefixEvidence = <String>[];
  for (var i = transcriptStart; i < transcriptAnchor; i++) {
    final word = transcriptUnits[i].word;
    if (word != null) prefixEvidence.add(word);
  }
  final suffixEvidence = <String>[];
  for (var i = transcriptAnchor + 1; i <= transcriptEnd; i++) {
    final word = transcriptUnits[i].word;
    if (word != null) suffixEvidence.add(word);
  }

  final prefixIndices = <int>[];
  for (var i = scriptStart; i < scriptAnchor; i++) {
    final unit = scriptUnits[i];
    for (var index = unit.start; index < unit.endExclusive; index++) {
      prefixIndices.add(index);
    }
  }
  final suffixIndices = <int>[];
  for (var i = scriptAnchor + 1; i <= scriptEnd; i++) {
    final unit = scriptUnits[i];
    for (var index = unit.start; index < unit.endExclusive; index++) {
      suffixIndices.add(index);
    }
  }

  final prefixTarget =
      prefixMatches == 0
          ? scriptUnits[scriptAnchor].start - 1
          : scriptUnits[scriptAnchor - 1].endExclusive - 1;
  final recoveryTarget =
      suffixMatches == 0
          ? prefixTarget
          : scriptUnits[scriptEnd].endExclusive - 1;
  return _NumberMismatchCandidate(
    prefixTargetIndex: prefixTarget,
    recoveryTargetIndex: recoveryTarget,
    candidateStartIndex: scriptUnits[scriptStart].start,
    numericScriptStart: scriptUnits[scriptAnchor].start,
    transcriptEndUnit: transcriptEnd,
    transcriptLastMeaningfulUnit: _lastMeaningfulUnitIndex(transcriptUnits),
    prefixLexicalMatches: prefixMatches,
    suffixLexicalMatches: suffixMatches,
    lexicalAverage: similarityTotal / lexicalMatches,
    prefixMatchedScriptIndices: prefixIndices,
    suffixMatchedScriptIndices: suffixIndices,
    prefixEvidence: prefixEvidence,
    suffixEvidence: suffixEvidence,
  );
}

double? _lexicalNumberContextSimilarity(
  _NumberAlignmentUnit heard,
  _NumberAlignmentUnit written, {
  required bool strictBulletMode,
}) {
  if (heard.isBoundary ||
      written.isBoundary ||
      heard.word == null ||
      written.word == null) {
    return null;
  }
  return _numberUnitSimilarity(
    heard,
    written,
    strictBulletMode: strictBulletMode,
  );
}

class _NumberMismatchCandidate {
  final int prefixTargetIndex;
  final int recoveryTargetIndex;
  final int candidateStartIndex;
  final int numericScriptStart;
  final int transcriptEndUnit;
  final int transcriptLastMeaningfulUnit;
  final int prefixLexicalMatches;
  final int suffixLexicalMatches;
  final double lexicalAverage;
  final List<int> prefixMatchedScriptIndices;
  final List<int> suffixMatchedScriptIndices;
  final List<String> prefixEvidence;
  final List<String> suffixEvidence;
  final AlignmentResult? result;

  const _NumberMismatchCandidate({
    required this.prefixTargetIndex,
    required this.recoveryTargetIndex,
    required this.candidateStartIndex,
    required this.numericScriptStart,
    required this.transcriptEndUnit,
    required this.transcriptLastMeaningfulUnit,
    required this.prefixLexicalMatches,
    required this.suffixLexicalMatches,
    required this.lexicalAverage,
    required this.prefixMatchedScriptIndices,
    required this.suffixMatchedScriptIndices,
    required this.prefixEvidence,
    required this.suffixEvidence,
    this.result,
  });

  int get lexicalMatches => prefixLexicalMatches + suffixLexicalMatches;
  bool get reachesTranscriptTail =>
      transcriptEndUnit == transcriptLastMeaningfulUnit;
  List<String> get evidenceWords => [...prefixEvidence, ...suffixEvidence];

  bool isBetterThan(_NumberMismatchCandidate other) {
    if (lexicalMatches != other.lexicalMatches) {
      return lexicalMatches > other.lexicalMatches;
    }
    if (suffixLexicalMatches != other.suffixLexicalMatches) {
      return suffixLexicalMatches > other.suffixLexicalMatches;
    }
    if (numericScriptStart != other.numericScriptStart) {
      return numericScriptStart < other.numericScriptStart;
    }
    return lexicalAverage > other.lexicalAverage;
  }

  bool hasEquivalentEvidenceQuality(_NumberMismatchCandidate other) =>
      lexicalMatches == other.lexicalMatches &&
      suffixLexicalMatches == other.suffixLexicalMatches &&
      (lexicalAverage - other.lexicalAverage).abs() < 0.0001;

  AlignmentResult toPendingResult({
    required SttThresholdFamily thresholdFamily,
    required SpokenNumberValue heard,
    required SpokenNumberValue written,
  }) => AlignmentResult(
    prefixTargetIndex,
    lexicalAverage,
    'NUMBER_MISMATCH_PENDING: heard=${heard.debugLabel} '
    'script=${written.debugLabel} prefix=$prefixLexicalMatches',
    SttAlignmentDecision.advance,
    SttAlignmentKind.numberMismatchRecovery,
    thresholdFamily,
    prefixMatchedScriptIndices,
    prefixEvidence,
    candidateStartIndex,
    prefixTargetIndex,
  );

  AlignmentResult toRecoveryResult({
    required SttThresholdFamily thresholdFamily,
    required SpokenNumberValue heard,
    required SpokenNumberValue written,
  }) => AlignmentResult(
    recoveryTargetIndex,
    lexicalAverage,
    'NUMBER_MISMATCH_RECOVERY: heard=${heard.debugLabel} '
    'script=${written.debugLabel} prefix=$prefixLexicalMatches '
    'suffix=$suffixLexicalMatches',
    SttAlignmentDecision.advance,
    SttAlignmentKind.numberMismatchRecovery,
    thresholdFamily,
    [...prefixMatchedScriptIndices, ...suffixMatchedScriptIndices],
    evidenceWords,
    candidateStartIndex,
    recoveryTargetIndex,
  );

  _NumberMismatchCandidate copyWithResult(AlignmentResult value) =>
      _NumberMismatchCandidate(
        prefixTargetIndex: prefixTargetIndex,
        recoveryTargetIndex: recoveryTargetIndex,
        candidateStartIndex: candidateStartIndex,
        numericScriptStart: numericScriptStart,
        transcriptEndUnit: transcriptEndUnit,
        transcriptLastMeaningfulUnit: transcriptLastMeaningfulUnit,
        prefixLexicalMatches: prefixLexicalMatches,
        suffixLexicalMatches: suffixLexicalMatches,
        lexicalAverage: lexicalAverage,
        prefixMatchedScriptIndices: prefixMatchedScriptIndices,
        suffixMatchedScriptIndices: suffixMatchedScriptIndices,
        prefixEvidence: prefixEvidence,
        suffixEvidence: suffixEvidence,
        result: value,
      );
}
