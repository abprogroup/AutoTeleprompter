part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttGate on TeleprompterNotifier {
  SttEvidenceGateDecision _evaluateSttGate({
    required SttEvidenceGateCandidate candidate,
    required SttRecognitionPolicy policy,
    required int currentIndex,
    required int advanceGuardIndex,
    required bool visibleSkipTargetTrusted,
  }) {
    return const SttEvidenceGateService().evaluateCandidate(
      candidate: candidate,
      policy: policy,
      trackingState: _sttEvidenceTrackingState,
      currentIndex: currentIndex,
      advanceGuardIndex: advanceGuardIndex,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
      maxLocalAdvanceWithoutWait:
          TeleprompterNotifier._maxLocalSttJumpWithoutWait,
    );
  }

  SttEvidenceGateDecision _evaluateSttNoMatchGate({
    required String transcript,
    required AlignmentResult alignment,
  }) {
    return const SttEvidenceGateService().evaluateNoMatch(
      transcript: transcript,
      alignment: alignment,
      trackingState: _sttEvidenceTrackingState,
    );
  }

  void _applyGateState(SttEvidenceGateDecision decision) {
    _sttEvidenceTrackingState = decision.nextState;
    if (decision.shouldReset) {
      _resetSequentialSttStreak();
      _sttReadingStandby = false;
    }
  }

  void _resetSttEvidenceGate() {
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
  }

  SttEvidenceGateCandidate _sequentialGateCandidate(
    _SequentialSttProgress sequential,
  ) {
    return SttEvidenceGateCandidate(
      targetIndex: sequential.targetIndex!,
      confidence: 1.0,
      debugInfo: sequential.debugInfo,
      kind: SttAlignmentKind.sequence,
      thresholdFamily: SttThresholdFamily.startAdvance,
      evidenceWords: sequential.evidenceWords,
      evidenceScoreOverride: sequential.evidenceScore,
      source: 'sequential',
    );
  }

  SttEvidenceGateCandidate _relockGateCandidate({
    required int targetIndex,
    required String transcript,
    required SttRecognitionPolicy policy,
  }) {
    final evidenceWords = SttRecognitionPolicyService.capTranscriptWords(
      transcript,
      maxWords: policy.visibleSkip.smallWords.clamp(1, 8).toInt(),
    )
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    return SttEvidenceGateCandidate(
      targetIndex: targetIndex,
      confidence: 1.0,
      debugInfo: 'RELOCK_${_lastRelockScope.toUpperCase()}',
      kind: SttAlignmentKind.visiblePhrase,
      thresholdFamily: SttThresholdFamily.visibleSkip,
      evidenceWords: evidenceWords,
      source: 'relock',
    );
  }
}
