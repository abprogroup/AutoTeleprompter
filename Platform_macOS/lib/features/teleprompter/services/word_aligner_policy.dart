part of 'word_aligner.dart';

class AlignmentResult {
  final int confirmedWordIndex;
  final double confidence;
  final String debugInfo;
  final SttAlignmentDecision decision;

  AlignmentResult(
    this.confirmedWordIndex,
    this.confidence, [
    this.debugInfo = '',
    this.decision = SttAlignmentDecision.advance,
  ]);

  bool get shouldAdvance => decision == SttAlignmentDecision.advance;
  bool get shouldEnterStandby => decision == SttAlignmentDecision.standby;
}

enum SttAlignmentDecision {
  wait,
  standby,
  advance,
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
