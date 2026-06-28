import 'package:autoteleprompter/features/teleprompter/services/stt_evidence_gate_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

const _policy = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: true,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(3, 2),
  safetyRecovery: SttEvidenceThreshold(2, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

const _visibleOffPolicy = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: false,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(3, 2),
  safetyRecovery: SttEvidenceThreshold(2, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

void main() {
  group('SttMovementPolicyService', () {
    const policy = SttMovementPolicyService();

    test('slow reading after lock-on advances one next word', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          71,
          0.96,
          'NEXT_WORD',
          SttAlignmentDecision.advance,
          SttAlignmentKind.nextWord,
          SttThresholdFamily.startAdvance,
          const [71],
          const ['it'],
          71,
          71,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.tracking,
        currentIndex: 70,
        advanceGuardIndex: 70,
        visibleSkipTargetTrusted: false,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.advance);
      expect(decision.reason, 'tracking_next_word');
    });

    test('locked state still requires startAdvance evidence', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          23,
          0.98,
          'HEADING_PREFIX_SKIP',
          SttAlignmentDecision.advance,
          SttAlignmentKind.headingPrefixSkip,
          SttThresholdFamily.startAdvance,
          const [22, 23],
          const ['thank', 'you'],
          22,
          23,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.locked,
        currentIndex: 17,
        advanceGuardIndex: 17,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.hold);
      expect(decision.reason, 'needs_more_startAdvance');
    });

    test('heading body with enough evidence can lock on', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          25,
          0.98,
          'HEADING_PREFIX_SKIP',
          SttAlignmentDecision.advance,
          SttAlignmentKind.headingPrefixSkip,
          SttThresholdFamily.startAdvance,
          const [22, 23, 25],
          const ['thank', 'you', 'good'],
          22,
          25,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.locked,
        currentIndex: 17,
        advanceGuardIndex: 17,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.advance);
      expect(decision.reason, 'profile_start_advance');
    });

    test('safetyRecovery cannot approve a visible-area jump', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          59,
          1.0,
          'LOCAL_RECOVERY_PHRASE',
          SttAlignmentDecision.advance,
          SttAlignmentKind.localRecoveryPhrase,
          SttThresholdFamily.safetyRecovery,
          const [57, 58, 59],
          const ['special', 'conversation', 'with'],
          57,
          59,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.recovering,
        currentIndex: 36,
        advanceGuardIndex: 36,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.block);
      expect(decision.reason, 'visible_requires_visible_threshold');
    });

    test('visible skip requires visible setting and threshold', () {
      final disabled = policy.evaluateCandidate(
        alignment: AlignmentResult(
          59,
          0.92,
          'NEAR_PHRASE_PRIORITY',
          SttAlignmentDecision.advance,
          SttAlignmentKind.visiblePhrase,
          SttThresholdFamily.visibleSkip,
          const [56, 57, 58, 59],
          const ['host', 'special', 'conversation', 'with'],
          56,
          59,
        ),
        policy: _visibleOffPolicy,
        trackingState: SttEvidenceTrackingState.offScript,
        currentIndex: 36,
        advanceGuardIndex: 36,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );
      final enabled = policy.evaluateCandidate(
        alignment: AlignmentResult(
          59,
          0.92,
          'NEAR_PHRASE_PRIORITY',
          SttAlignmentDecision.advance,
          SttAlignmentKind.visiblePhrase,
          SttThresholdFamily.visibleSkip,
          const [56, 57, 58, 59],
          const ['host', 'special', 'conversation', 'with'],
          56,
          59,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.offScript,
        currentIndex: 36,
        advanceGuardIndex: 36,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(disabled.action, SttMovementAction.block);
      expect(enabled.action, SttMovementAction.advance);
      expect(enabled.reason, 'profile_visible_skip');
    });

    test('off-script speech resets and future one-word match cannot jump', () {
      final reset = policy.evaluateNoCandidate(
        transcript: 'random operator comment',
        alignment: AlignmentResult(
          36,
          0.1,
          'NO_MATCH',
          SttAlignmentDecision.wait,
        ),
        trackingState: SttEvidenceTrackingState.tracking,
        preserveSlowContext: false,
        repeatedTranscript: false,
      );
      final luckyFutureWord = policy.evaluateCandidate(
        alignment: AlignmentResult(
          80,
          0.94,
          'SINGLE',
          SttAlignmentDecision.advance,
          SttAlignmentKind.singleWord,
          SttThresholdFamily.startAdvance,
          const [80],
          const ['foreign'],
          80,
          80,
        ),
        policy: _policy,
        trackingState: reset.nextState,
        currentIndex: 36,
        advanceGuardIndex: 36,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(reset.action, SttMovementAction.reset);
      expect(luckyFutureWord.action, SttMovementAction.block);
    });
  });
}
