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
    required Script script,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
  }) {
    final preserveTrackingContext = WordAligner.shouldPreserveSlowContext(
      script: script.words,
      transcript: transcript,
      lastConfirmedIndex: _currentState.confirmedWordIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    return const SttEvidenceGateService().evaluateNoMatch(
      transcript: transcript,
      alignment: alignment,
      trackingState: _sttEvidenceTrackingState,
      preserveTrackingContext: preserveTrackingContext,
    );
  }

  void _applyGateState(SttEvidenceGateDecision decision) {
    _sttEvidenceTrackingState = decision.nextState;
    if (decision.shouldAdvance ||
        decision.action == SttEvidenceGateAction.block ||
        decision.shouldReset) {
      _resetPendingStartEvidence();
    }
    if (decision.shouldReset) {
      _resetSequentialSttStreak();
      _sttReadingStandby = false;
    }
  }

  void _resetSttEvidenceGate() {
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
    _resetPendingStartEvidence();
  }

  void _rememberPendingStartEvidence({
    required SttEvidenceGateDecision decision,
    required SttEvidenceGateCandidate candidate,
    required int currentIndex,
  }) {
    if (decision.action != SttEvidenceGateAction.hold ||
        decision.thresholdLabel != 'startAdvance' ||
        decision.evidenceScore <= 0 ||
        candidate.targetIndex <= currentIndex) {
      return;
    }
    _pendingStartEvidenceBaseIndex = currentIndex;
    _pendingStartEvidenceTargetIndex = candidate.targetIndex;
    _pendingStartEvidenceScore = decision.evidenceScore;
    _pendingStartEvidenceWords =
        List<String>.unmodifiable(candidate.evidenceWords);
    _pendingStartEvidenceAt = DateTime.now();
  }

  SttEvidenceGateCandidate? _pendingStartEvidenceContinuation({
    required Script script,
    required String transcript,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
  }) {
    final baseIndex = _pendingStartEvidenceBaseIndex;
    final targetIndex = _pendingStartEvidenceTargetIndex;
    final lastAt = _pendingStartEvidenceAt;
    if (baseIndex == null || targetIndex == null || lastAt == null) {
      return null;
    }
    if (baseIndex != _currentState.confirmedWordIndex ||
        DateTime.now().difference(lastAt) >
            TeleprompterNotifier._pendingStartEvidenceGrace) {
      _resetPendingStartEvidence();
      return null;
    }
    final continued = WordAligner.continuePendingStartEvidence(
      script: script.words,
      transcript: transcript,
      pendingTargetIndex: targetIndex,
      strictBulletMode: strictBulletMode,
    );
    if (continued == null ||
        continued.confirmedWordIndex <= targetIndex ||
        continued.evidenceWords.isEmpty) {
      return null;
    }
    final continuationScore =
        policy.startAdvance.evidenceScore(continued.evidenceWords);
    final combinedScore = _pendingStartEvidenceScore + continuationScore;
    final combinedWords = [
      ..._pendingStartEvidenceWords,
      ...continued.evidenceWords,
    ];
    return SttEvidenceGateCandidate(
      targetIndex: continued.confirmedWordIndex,
      confidence: continued.confidence,
      debugInfo:
          '${continued.debugInfo} | pending=${_pendingStartEvidenceScore.toStringAsFixed(1)} + '
          '${continuationScore.toStringAsFixed(1)}',
      kind: continued.kind,
      thresholdFamily: SttThresholdFamily.startAdvance,
      matchedScriptIndices: continued.matchedScriptIndices,
      evidenceWords: List<String>.unmodifiable(combinedWords),
      candidateStartIndex: continued.candidateStartIndex,
      candidateEndIndex: continued.candidateEndIndex,
      evidenceScoreOverride: combinedScore,
      source: 'pending-start',
    );
  }

  void _resetPendingStartEvidence() {
    _pendingStartEvidenceBaseIndex = null;
    _pendingStartEvidenceTargetIndex = null;
    _pendingStartEvidenceScore = 0.0;
    _pendingStartEvidenceWords = const [];
    _pendingStartEvidenceAt = null;
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
