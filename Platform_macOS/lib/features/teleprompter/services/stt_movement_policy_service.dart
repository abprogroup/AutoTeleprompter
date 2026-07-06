import 'stt_tracking_state.dart';
import 'word_aligner.dart';

enum SttMovementAction {
  advance,
  hold,
  reset,
  block,
}

class SttMovementDecision {
  final SttMovementAction action;
  final SttEvidenceTrackingState nextState;
  final int targetIndex;
  final String label;
  final String reason;
  final String thresholdLabel;
  final double evidenceScore;
  final double neededScore;

  const SttMovementDecision({
    required this.action,
    required this.nextState,
    required this.targetIndex,
    required this.label,
    required this.reason,
    required this.thresholdLabel,
    required this.evidenceScore,
    required this.neededScore,
  });

  bool get shouldAdvance => action == SttMovementAction.advance;
  bool get shouldReset => action == SttMovementAction.reset;
  bool get shouldBlock => action == SttMovementAction.block;

  String get debugSummary {
    final score = evidenceScore.toStringAsFixed(1);
    final needed = neededScore.toStringAsFixed(1);
    return '$label rule=$reason state=${nextState.name} '
        'family=$thresholdLabel evidence=$score/$needed target=$targetIndex';
  }
}

class SttMovementPolicyService {
  const SttMovementPolicyService();

  SttMovementDecision evaluateCandidate({
    required AlignmentResult alignment,
    required SttRecognitionPolicy policy,
    required SttEvidenceTrackingState trackingState,
    required int currentIndex,
    required int advanceGuardIndex,
    required bool visibleSkipTargetTrusted,
    required int maxLocalAdvanceWithoutWait,
  }) {
    final target = alignment.confirmedWordIndex;
    if (target <= advanceGuardIndex || target <= currentIndex) {
      return _decision(
        action: SttMovementAction.hold,
        nextState: _preservedState(trackingState),
        targetIndex: target,
        label: 'TRACK_HOLD',
        reason: 'not_ahead',
      );
    }

    final jump = target - advanceGuardIndex;
    final structuralLocal = _isStructuralLocal(alignment.kind);
    final localContinuation = _isLocalContinuation(
      alignment,
      advanceGuardIndex,
      maxLocalAdvanceWithoutWait,
    );
    final cleanTrackingNext = _canAdvanceCleanTrackingNext(
      alignment,
      trackingState,
      jump,
      maxLocalAdvanceWithoutWait,
    );

    var family = _effectiveFamily(
      alignment: alignment,
      trackingState: trackingState,
      localContinuation: localContinuation,
      jump: jump,
      maxLocalAdvanceWithoutWait: maxLocalAdvanceWithoutWait,
    );

    final requiresVisibleThreshold = visibleSkipTargetTrusted &&
        jump > maxLocalAdvanceWithoutWait &&
        !structuralLocal &&
        !localContinuation;
    final visibleFamily = requiresVisibleThreshold ||
        family == SttThresholdFamily.visibleSkip ||
        alignment.kind == SttAlignmentKind.visiblePhrase ||
        alignment.kind == SttAlignmentKind.sentenceRecovery;
    final unsafeOffscreenJump = !visibleSkipTargetTrusted &&
        jump > maxLocalAdvanceWithoutWait &&
        !structuralLocal &&
        !localContinuation;

    if (visibleFamily) {
      family = SttThresholdFamily.visibleSkip;
      if (!policy.visibleSkipEnabled) {
        return _decision(
          action: SttMovementAction.block,
          nextState: SttEvidenceTrackingState.offScript,
          targetIndex: target,
          label: 'TRACK_BLOCK_VISIBLE',
          reason: 'visible_skip_disabled',
        );
      }
      if (!visibleSkipTargetTrusted) {
        return _decision(
          action: SttMovementAction.block,
          nextState: SttEvidenceTrackingState.offScript,
          targetIndex: target,
          label: 'TRACK_BLOCK_VISIBLE',
          reason: 'visible_target_untrusted',
        );
      }
    } else if (unsafeOffscreenJump) {
      return _decision(
        action: SttMovementAction.block,
        nextState: SttEvidenceTrackingState.offScript,
        targetIndex: target,
        label: 'TRACK_BLOCK_VISIBLE',
        reason: 'offscreen_jump_blocked',
      );
    }

    if (cleanTrackingNext) {
      return _decision(
        action: SttMovementAction.advance,
        nextState: SttEvidenceTrackingState.tracking,
        targetIndex: target,
        label: 'TRACK_ADVANCE',
        reason: 'tracking_next_word',
        thresholdLabel: 'tracking-next',
        evidenceScore: 1,
        neededScore: 1,
      );
    }

    final threshold = _thresholdFor(policy, family);
    final evidenceScore = threshold.evidenceScore(alignment.evidenceWords);
    final neededScore = threshold.smallWords.toDouble();
    if (evidenceScore >= neededScore) {
      return _decision(
        action: SttMovementAction.advance,
        nextState: SttEvidenceTrackingState.tracking,
        targetIndex: target,
        label: 'TRACK_ADVANCE',
        reason: _reasonForFamily(family),
        thresholdLabel: _labelForFamily(family),
        evidenceScore: evidenceScore,
        neededScore: neededScore,
      );
    }

    return _decision(
      action: SttMovementAction.hold,
      nextState: _holdState(trackingState),
      targetIndex: target,
      label: 'TRACK_HOLD',
      reason: 'needs_more_${_labelForFamily(family)}',
      thresholdLabel: _labelForFamily(family),
      evidenceScore: evidenceScore,
      neededScore: neededScore,
    );
  }

  SttMovementDecision evaluateNoCandidate({
    required String transcript,
    required AlignmentResult alignment,
    required SttEvidenceTrackingState trackingState,
    required bool preserveSlowContext,
    required bool repeatedTranscript,
  }) {
    final heardSomething = transcript.trim().isNotEmpty;
    final partialEvidence = alignment.debugInfo.startsWith('WAIT_EVIDENCE') ||
        alignment.debugInfo.startsWith('EMPTY') ||
        alignment.debugInfo.startsWith('AT_END');
    if (!heardSomething || repeatedTranscript || partialEvidence) {
      return _decision(
        action: SttMovementAction.hold,
        nextState: _preservedState(trackingState),
        targetIndex: alignment.confirmedWordIndex,
        label: 'TRACK_HOLD',
        reason: repeatedTranscript
            ? 'repeated_partial'
            : 'waiting_for_profile_evidence',
      );
    }

    if (preserveSlowContext &&
        trackingState != SttEvidenceTrackingState.locked &&
        trackingState != SttEvidenceTrackingState.offScript) {
      return _decision(
        action: SttMovementAction.hold,
        nextState: SttEvidenceTrackingState.recovering,
        targetIndex: alignment.confirmedWordIndex,
        label: 'TRACK_HOLD',
        reason: 'slow_context_waiting',
      );
    }

    return _decision(
      action: SttMovementAction.reset,
      nextState: SttEvidenceTrackingState.offScript,
      targetIndex: alignment.confirmedWordIndex,
      label: 'TRACK_RESET_OFF_SCRIPT',
      reason: 'speech_not_in_current_path',
    );
  }

  SttThresholdFamily _effectiveFamily({
    required AlignmentResult alignment,
    required SttEvidenceTrackingState trackingState,
    required bool localContinuation,
    required int jump,
    required int maxLocalAdvanceWithoutWait,
  }) {
    var family = alignment.thresholdFamily;
    if (family == SttThresholdFamily.none) {
      family = SttThresholdFamily.startAdvance;
    }
    if (alignment.kind == SttAlignmentKind.headingPrefixSkip) {
      return SttThresholdFamily.startAdvance;
    }
    if (family == SttThresholdFamily.visibleSkip &&
        jump <= maxLocalAdvanceWithoutWait) {
      family = trackingState == SttEvidenceTrackingState.tracking ||
              trackingState == SttEvidenceTrackingState.recovering
          ? SttThresholdFamily.safetyRecovery
          : SttThresholdFamily.startAdvance;
    }
    if (trackingState == SttEvidenceTrackingState.locked ||
        trackingState == SttEvidenceTrackingState.offScript) {
      return family == SttThresholdFamily.visibleSkip
          ? SttThresholdFamily.visibleSkip
          : SttThresholdFamily.startAdvance;
    }
    if (localContinuation && family == SttThresholdFamily.startAdvance) {
      return SttThresholdFamily.safetyRecovery;
    }
    return family;
  }

  bool _canAdvanceCleanTrackingNext(
    AlignmentResult alignment,
    SttEvidenceTrackingState trackingState,
    int jump,
    int maxLocalAdvanceWithoutWait,
  ) {
    if (trackingState != SttEvidenceTrackingState.tracking &&
        trackingState != SttEvidenceTrackingState.recovering) {
      return false;
    }
    if (jump > maxLocalAdvanceWithoutWait) return false;
    if (alignment.confidence < 0.70) return false;
    return alignment.kind == SttAlignmentKind.nextWord ||
        alignment.kind == SttAlignmentKind.nextWordLowEvidence ||
        alignment.kind == SttAlignmentKind.singleWord;
  }

  bool _isLocalContinuation(
    AlignmentResult alignment,
    int advanceGuardIndex,
    int maxLocalAdvanceWithoutWait,
  ) {
    if (alignment.thresholdFamily == SttThresholdFamily.visibleSkip) {
      return false;
    }
    final start = alignment.candidateStartIndex;
    if (start == null) return false;
    return start <= advanceGuardIndex + maxLocalAdvanceWithoutWait + 1;
  }

  bool _isStructuralLocal(SttAlignmentKind kind) =>
      kind == SttAlignmentKind.headingPrefixSkip ||
      kind == SttAlignmentKind.confirmedTailBridge ||
      kind == SttAlignmentKind.nameRunBodyBridge;

  SttEvidenceTrackingState _preservedState(SttEvidenceTrackingState state) =>
      state == SttEvidenceTrackingState.locked ||
              state == SttEvidenceTrackingState.offScript
          ? state
          : SttEvidenceTrackingState.tracking;

  SttEvidenceTrackingState _holdState(SttEvidenceTrackingState state) =>
      state == SttEvidenceTrackingState.locked ||
              state == SttEvidenceTrackingState.offScript
          ? state
          : SttEvidenceTrackingState.recovering;

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

  SttMovementDecision _decision({
    required SttMovementAction action,
    required SttEvidenceTrackingState nextState,
    required int targetIndex,
    required String label,
    required String reason,
    String thresholdLabel = 'none',
    double evidenceScore = 0,
    double neededScore = 0,
  }) {
    return SttMovementDecision(
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
