part of 'word_aligner.dart';

class AlignmentResult {
  final int confirmedWordIndex;
  final double confidence;
  final String debugInfo;
  final SttAlignmentDecision decision;
  final SttAlignmentKind kind;
  final SttThresholdFamily thresholdFamily;
  final List<int> matchedScriptIndices;
  final List<String> evidenceWords;
  final int? candidateStartIndex;
  final int? candidateEndIndex;

  AlignmentResult(
    this.confirmedWordIndex,
    this.confidence, [
    this.debugInfo = '',
    this.decision = SttAlignmentDecision.advance,
    this.kind = SttAlignmentKind.unknown,
    this.thresholdFamily = SttThresholdFamily.none,
    this.matchedScriptIndices = const [],
    this.evidenceWords = const [],
    this.candidateStartIndex,
    this.candidateEndIndex,
  ]);

  bool get shouldAdvance => decision == SttAlignmentDecision.advance;
  bool get shouldEnterStandby => decision == SttAlignmentDecision.standby;

  AlignmentResult copyWith({
    int? confirmedWordIndex,
    double? confidence,
    String? debugInfo,
    SttAlignmentDecision? decision,
    SttAlignmentKind? kind,
    SttThresholdFamily? thresholdFamily,
    List<int>? matchedScriptIndices,
    List<String>? evidenceWords,
    int? candidateStartIndex,
    int? candidateEndIndex,
  }) {
    return AlignmentResult(
      confirmedWordIndex ?? this.confirmedWordIndex,
      confidence ?? this.confidence,
      debugInfo ?? this.debugInfo,
      decision ?? this.decision,
      kind ?? this.kind,
      thresholdFamily ?? this.thresholdFamily,
      matchedScriptIndices ?? this.matchedScriptIndices,
      evidenceWords ?? this.evidenceWords,
      candidateStartIndex ?? this.candidateStartIndex,
      candidateEndIndex ?? this.candidateEndIndex,
    );
  }
}

enum SttAlignmentDecision {
  wait,
  standby,
  advance,
}

enum SttAlignmentKind {
  unknown,
  nextWordLowEvidence,
  nextWord,
  singleWord,
  nextPhrase,
  localRecoveryPhrase,
  visiblePhrase,
  sequence,
  sentenceRecovery,
  headingPrefixSkip,
  confirmedTailBridge,
  nameRunBodyBridge,
}

enum SttThresholdFamily {
  none,
  startAdvance,
  safetyRecovery,
  bulletAdvance,
  visibleSkip,
}

class SttEvidenceThreshold {
  final int smallWords;
  final int bigWords;
  final int bigWordMinLetters;

  const SttEvidenceThreshold(
    this.smallWords, [
    int? bigWords,
    this.bigWordMinLetters = 5,
  ]) : bigWords = bigWords ?? (smallWords <= 2 ? 1 : smallWords - 1);

  double get _bigWordWeight => smallWords / bigWords.clamp(1, 99);

  bool passes(Iterable<String> normalizedWords) =>
      evidenceScore(normalizedWords) >= smallWords;

  double evidenceScore(Iterable<String> normalizedWords) {
    var score = 0.0;
    for (final word in normalizedWords) {
      if (word.isEmpty) continue;
      score += evidenceCost(word);
    }
    return score;
  }

  double evidenceCost(String normalizedWord) {
    if (normalizedWord.isEmpty) return 0.0;
    return WordAligner.isBigRecognitionWord(
      normalizedWord,
      minLetters: bigWordMinLetters,
    )
        ? _bigWordWeight
        : 1.0;
  }

  String get label => '$smallWords small / $bigWords big';
}

class SttRecognitionPolicy {
  final bool bulletMode;
  final bool visibleSkipEnabled;
  final bool hardVisibleSkipEnabled;
  final SttEvidenceThreshold startAdvance;
  final SttEvidenceThreshold safetyRecovery;
  final SttEvidenceThreshold bulletAdvance;
  final SttEvidenceThreshold visibleSkip;

  const SttRecognitionPolicy({
    required this.bulletMode,
    required this.visibleSkipEnabled,
    required this.hardVisibleSkipEnabled,
    this.startAdvance = const SttEvidenceThreshold(4),
    this.safetyRecovery = const SttEvidenceThreshold(2),
    this.bulletAdvance = const SttEvidenceThreshold(3),
    SttEvidenceThreshold? visibleSkip,
  }) : visibleSkip = visibleSkip ??
            (hardVisibleSkipEnabled
                ? const SttEvidenceThreshold(5)
                : const SttEvidenceThreshold(4));

  factory SttRecognitionPolicy.legacy({
    bool strictBulletMode = false,
    bool visibleSkipEnabled = false,
    bool hardVisibleSkipEnabled = false,
  }) {
    return SttRecognitionPolicy(
      bulletMode: strictBulletMode,
      visibleSkipEnabled: visibleSkipEnabled,
      hardVisibleSkipEnabled: hardVisibleSkipEnabled && visibleSkipEnabled,
    );
  }

  SttEvidenceThreshold localThreshold({required bool readingStandby}) {
    if (bulletMode) return bulletAdvance;
    return readingStandby ? safetyRecovery : startAdvance;
  }
}
