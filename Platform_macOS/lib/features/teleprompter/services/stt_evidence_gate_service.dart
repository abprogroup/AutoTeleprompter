import 'word_aligner.dart';

enum SttEvidenceTrackingState {
  locked,
  tracking,
  recovering,
  offScript,
}

enum SttEvidenceGateAction {
  advance,
  hold,
  reset,
  block,
}

class SttEvidenceGateCandidate {
  final int targetIndex;
  final double confidence;
  final String debugInfo;
  final SttAlignmentKind kind;
  final SttThresholdFamily thresholdFamily;
  final List<int> matchedScriptIndices;
  final List<String> evidenceWords;
  final int? candidateStartIndex;
  final int? candidateEndIndex;
  final double? evidenceScoreOverride;
  final String source;

  const SttEvidenceGateCandidate({
    required this.targetIndex,
    required this.confidence,
    required this.debugInfo,
    required this.kind,
    required this.thresholdFamily,
    this.matchedScriptIndices = const [],
    this.evidenceWords = const [],
    this.candidateStartIndex,
    this.candidateEndIndex,
    this.evidenceScoreOverride,
    this.source = 'aligner',
  });

  factory SttEvidenceGateCandidate.fromAlignment(
    AlignmentResult result, {
    String source = 'aligner',
  }) {
    return SttEvidenceGateCandidate(
      targetIndex: result.confirmedWordIndex,
      confidence: result.confidence,
      debugInfo: result.debugInfo,
      kind: result.kind,
      thresholdFamily: result.thresholdFamily,
      matchedScriptIndices: result.matchedScriptIndices,
      evidenceWords: result.evidenceWords,
      candidateStartIndex: result.candidateStartIndex,
      candidateEndIndex: result.candidateEndIndex,
      source: source,
    );
  }
}

class SttEvidenceGateDecision {
  final SttEvidenceGateAction action;
  final SttEvidenceTrackingState nextState;
  final int targetIndex;
  final String label;
  final String reason;
  final String thresholdLabel;
  final double evidenceScore;
  final double neededScore;

  const SttEvidenceGateDecision({
    required this.action,
    required this.nextState,
    required this.targetIndex,
    required this.label,
    required this.reason,
    required this.thresholdLabel,
    required this.evidenceScore,
    required this.neededScore,
  });

  bool get shouldAdvance => action == SttEvidenceGateAction.advance;
  bool get shouldReset => action == SttEvidenceGateAction.reset;

  String get debugSummary {
    final score = evidenceScore.toStringAsFixed(1);
    final needed = neededScore.toStringAsFixed(1);
    return '$label rule=$reason state=${nextState.name} '
        'family=$thresholdLabel evidence=$score/$needed target=$targetIndex';
  }
}

class SttEvidenceGateService {
  const SttEvidenceGateService();

  SttEvidenceGateDecision evaluateCandidate({
    required SttEvidenceGateCandidate candidate,
    required SttRecognitionPolicy policy,
    required SttEvidenceTrackingState trackingState,
    required int currentIndex,
    required int advanceGuardIndex,
    required bool visibleSkipTargetTrusted,
    required int maxLocalAdvanceWithoutWait,
  }) {
    final target = candidate.targetIndex;
    if (target <= advanceGuardIndex || target <= currentIndex) {
      return _decision(
        action: SttEvidenceGateAction.hold,
        nextState: trackingState == SttEvidenceTrackingState.tracking
            ? SttEvidenceTrackingState.tracking
            : SttEvidenceTrackingState.recovering,
        targetIndex: target,
        label: 'GATE_HOLD',
        reason: 'not_ahead',
      );
    }

    final jump = target - advanceGuardIndex;
    final structuralLocal = _isStructuralLocal(candidate.kind);
    final localContinuation = _isLocalContinuation(
      candidate,
      advanceGuardIndex,
      maxLocalAdvanceWithoutWait,
    );
    final visibleJump = visibleSkipTargetTrusted &&
        jump > maxLocalAdvanceWithoutWait &&
        !localContinuation;
    final offscreenJump = !visibleSkipTargetTrusted &&
        jump > maxLocalAdvanceWithoutWait &&
        !localContinuation;
    final cleanTrackingNext =
        (trackingState == SttEvidenceTrackingState.tracking ||
                trackingState == SttEvidenceTrackingState.recovering) &&
            jump <= maxLocalAdvanceWithoutWait &&
            _isCleanNextCandidate(candidate.kind) &&
            candidate.confidence >= 0.70;

    var family = candidate.thresholdFamily;
    if (family == SttThresholdFamily.none) {
      family = SttThresholdFamily.startAdvance;
    }
    if (family == SttThresholdFamily.visibleSkip &&
        jump <= maxLocalAdvanceWithoutWait) {
      family = trackingState == SttEvidenceTrackingState.tracking
          ? SttThresholdFamily.safetyRecovery
          : SttThresholdFamily.startAdvance;
    }
    if (family == SttThresholdFamily.startAdvance &&
        trackingState == SttEvidenceTrackingState.recovering &&
        localContinuation) {
      family = SttThresholdFamily.safetyRecovery;
    }
    if ((trackingState == SttEvidenceTrackingState.locked ||
            trackingState == SttEvidenceTrackingState.offScript) &&
        family != SttThresholdFamily.visibleSkip) {
      family = SttThresholdFamily.startAdvance;
    }
    if (candidate.kind == SttAlignmentKind.headingPrefixSkip) {
      family = SttThresholdFamily.startAdvance;
    }

    if (family == SttThresholdFamily.visibleSkip &&
        !policy.visibleSkipEnabled) {
      return _decision(
        action: SttEvidenceGateAction.block,
        nextState: SttEvidenceTrackingState.offScript,
        targetIndex: target,
        label: 'GATE_BLOCK_VISIBLE',
        reason: 'visible_skip_disabled',
      );
    }

    if (visibleJump &&
        family != SttThresholdFamily.visibleSkip &&
        !structuralLocal) {
      return _decision(
        action: SttEvidenceGateAction.block,
        nextState: SttEvidenceTrackingState.offScript,
        targetIndex: target,
        label: 'GATE_BLOCK_VISIBLE',
        reason: 'visible_requires_visible_threshold',
      );
    }
    if (offscreenJump && !structuralLocal) {
      return _decision(
        action: SttEvidenceGateAction.block,
        nextState: SttEvidenceTrackingState.offScript,
        targetIndex: target,
        label: 'GATE_BLOCK_OFFSCREEN',
        reason: 'offscreen_jump',
      );
    }
    if (cleanTrackingNext) {
      return _decision(
        action: SttEvidenceGateAction.advance,
        nextState: SttEvidenceTrackingState.tracking,
        targetIndex: target,
        label: 'GATE_ADVANCE',
        reason: 'tracking_next_word',
        thresholdLabel: 'tracking-next',
        evidenceScore: 1,
        neededScore: 1,
      );
    }

    final threshold = _thresholdFor(policy, family);
    final evidenceScore = candidate.evidenceScoreOverride ??
        threshold.evidenceScore(candidate.evidenceWords);
    final neededScore = threshold.smallWords.toDouble();
    if (evidenceScore >= neededScore) {
      return _decision(
        action: SttEvidenceGateAction.advance,
        nextState: SttEvidenceTrackingState.tracking,
        targetIndex: target,
        label: 'GATE_ADVANCE',
        reason: _reasonForFamily(family),
        thresholdLabel: _labelForFamily(family),
        evidenceScore: evidenceScore,
        neededScore: neededScore,
      );
    }

    return _decision(
      action: SttEvidenceGateAction.hold,
      nextState: SttEvidenceTrackingState.recovering,
      targetIndex: target,
      label: 'GATE_HOLD',
      reason: 'needs_more_${_labelForFamily(family)}',
      thresholdLabel: _labelForFamily(family),
      evidenceScore: evidenceScore,
      neededScore: neededScore,
    );
  }

  SttEvidenceGateDecision evaluateNoMatch({
    required String transcript,
    required AlignmentResult alignment,
    required SttEvidenceTrackingState trackingState,
    bool preserveTrackingContext = false,
  }) {
    final heardSomething = transcript.trim().isNotEmpty;
    final debug = alignment.debugInfo;
    final partialEvidence = debug.startsWith('WAIT_EVIDENCE') ||
        debug.startsWith('EMPTY') ||
        debug.startsWith('AT_END');
    if (!heardSomething ||
        (partialEvidence && trackingState == SttEvidenceTrackingState.locked)) {
      return _decision(
        action: SttEvidenceGateAction.hold,
        nextState: trackingState,
        targetIndex: alignment.confirmedWordIndex,
        label: 'GATE_HOLD',
        reason: 'waiting_for_profile_evidence',
      );
    }
    if (preserveTrackingContext &&
        (trackingState == SttEvidenceTrackingState.tracking ||
            trackingState == SttEvidenceTrackingState.recovering)) {
      return _decision(
        action: SttEvidenceGateAction.hold,
        nextState: SttEvidenceTrackingState.recovering,
        targetIndex: alignment.confirmedWordIndex,
        label: 'GATE_HOLD',
        reason: 'local_context_waiting',
      );
    }
    if (debug.startsWith('NO_MATCH') || debug.startsWith('WAIT_EVIDENCE')) {
      return _decision(
        action: SttEvidenceGateAction.reset,
        nextState: SttEvidenceTrackingState.offScript,
        targetIndex: alignment.confirmedWordIndex,
        label: 'GATE_RESET_OFF_SCRIPT',
        reason: 'speech_not_in_current_path',
      );
    }
    return _decision(
      action: SttEvidenceGateAction.hold,
      nextState: SttEvidenceTrackingState.recovering,
      targetIndex: alignment.confirmedWordIndex,
      label: 'GATE_HOLD',
      reason: 'no_candidate',
    );
  }

  SttEvidenceThreshold _thresholdFor(
    SttRecognitionPolicy policy,
    SttThresholdFamily family,
  ) {
    switch (family) {
      case SttThresholdFamily.safetyRecovery:
        return policy.safetyRecovery;
      case SttThresholdFamily.bulletAdvance:
        return policy.bulletAdvance;
      case SttThresholdFamily.visibleSkip:
        return policy.visibleSkip;
      case SttThresholdFamily.startAdvance:
      case SttThresholdFamily.none:
        return policy.startAdvance;
    }
  }

  bool _isCleanNextCandidate(SttAlignmentKind kind) {
    return kind == SttAlignmentKind.nextWord ||
        kind == SttAlignmentKind.nextWordLowEvidence ||
        kind == SttAlignmentKind.singleWord;
  }

  bool _isStructuralLocal(SttAlignmentKind kind) {
    return kind == SttAlignmentKind.headingPrefixSkip ||
        kind == SttAlignmentKind.confirmedTailBridge ||
        kind == SttAlignmentKind.nameRunBodyBridge;
  }

  bool _isLocalContinuation(
    SttEvidenceGateCandidate candidate,
    int advanceGuardIndex,
    int maxLocalAdvanceWithoutWait,
  ) {
    if (candidate.thresholdFamily == SttThresholdFamily.visibleSkip) {
      return false;
    }
    final start = candidate.candidateStartIndex;
    if (start == null) return false;
    return start <= advanceGuardIndex + maxLocalAdvanceWithoutWait + 1;
  }

  String _labelForFamily(SttThresholdFamily family) {
    switch (family) {
      case SttThresholdFamily.safetyRecovery:
        return 'safetyRecovery';
      case SttThresholdFamily.bulletAdvance:
        return 'bulletAdvance';
      case SttThresholdFamily.visibleSkip:
        return 'visibleSkip';
      case SttThresholdFamily.startAdvance:
      case SttThresholdFamily.none:
        return 'startAdvance';
    }
  }

  String _reasonForFamily(SttThresholdFamily family) {
    switch (family) {
      case SttThresholdFamily.safetyRecovery:
        return 'profile_safety_recovery';
      case SttThresholdFamily.bulletAdvance:
        return 'profile_bullet_advance';
      case SttThresholdFamily.visibleSkip:
        return 'profile_visible_skip';
      case SttThresholdFamily.startAdvance:
      case SttThresholdFamily.none:
        return 'profile_start_advance';
    }
  }

  SttEvidenceGateDecision _decision({
    required SttEvidenceGateAction action,
    required SttEvidenceTrackingState nextState,
    required int targetIndex,
    required String label,
    required String reason,
    String thresholdLabel = 'none',
    double evidenceScore = 0,
    double neededScore = 0,
  }) {
    return SttEvidenceGateDecision(
      action: action,
      nextState: nextState,
      targetIndex: targetIndex,
      label: label,
      reason: reason,
      thresholdLabel: thresholdLabel,
      evidenceScore: evidenceScore,
      neededScore: neededScore,
    );
  }
}
