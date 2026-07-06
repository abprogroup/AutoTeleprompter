import 'package:autoteleprompter/core/extensions/string_extensions.dart';
import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_tracking_state.dart';
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

ScriptWord _word(String raw, int index) {
  return ScriptWord(
    raw: raw,
    normalized: raw.normalizeForMatching(),
    index: index,
    isRtl: false,
  );
}

List<ScriptWord> _openingRemarksScript() {
  final raw = [
    '1.',
    '-',
    'Opening',
    'Remarks',
    'Thank',
    'you,',
    'Naveh',
    'Dromi.',
    'Good',
    'afternoon,',
    'everyone.',
  ];
  return [
    for (var i = 0; i < raw.length; i++) _word(raw[i], i),
  ];
}

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

    test('pending heading evidence can complete after a damaged name', () {
      final words = _openingRemarksScript();
      final first = WordAligner.align(
        script: words,
        transcript: 'Thank you',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 0,
        maxSkipTargetIndex: words.length - 1,
        policy: _policy,
      );
      final firstDecision = policy.evaluateCandidate(
        alignment: first,
        policy: _policy,
        trackingState: SttEvidenceTrackingState.locked,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(first.confirmedWordIndex, 5);
      expect(firstDecision.action, SttMovementAction.hold);
      expect(firstDecision.reason, 'needs_more_startAdvance');

      final continued = WordAligner.continuePendingStartEvidence(
        script: words,
        transcript: 'thank you aveda romy good afternoon everyone',
        pendingTargetIndex: first.confirmedWordIndex,
      );
      expect(continued, isNotNull);
      expect(continued!.debugInfo, contains('CONTINUED_START'));

      final continuedDecision = policy.evaluateCandidate(
        alignment: continued,
        policy: _policy,
        trackingState: SttEvidenceTrackingState.locked,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(continuedDecision.action, SttMovementAction.advance);
      expect(continuedDecision.reason, 'profile_start_advance');
    });

    test('safetyRecovery cannot approve a visible-area jump by itself', () {
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

      expect(decision.action, SttMovementAction.hold);
      expect(decision.reason, 'needs_more_visibleSkip');
    });

    test('tracking local next phrase uses safetyRecovery, not visibleSkip', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          31,
          0.92,
          'NEXT_PHRASE',
          SttAlignmentDecision.advance,
          SttAlignmentKind.nextPhrase,
          SttThresholdFamily.safetyRecovery,
          const [29, 30, 31],
          const ['its', 'a', 'pleasure'],
          29,
          31,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.tracking,
        currentIndex: 28,
        advanceGuardIndex: 28,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.advance);
      expect(decision.reason, 'profile_safety_recovery');
    });

    test('trusted visible local-recovery candidate uses visible threshold', () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          59,
          1.0,
          'LOCAL_RECOVERY_PHRASE',
          SttAlignmentDecision.advance,
          SttAlignmentKind.localRecoveryPhrase,
          SttThresholdFamily.safetyRecovery,
          const [56, 57, 58, 59],
          const ['host', 'special', 'conversation', 'with'],
          56,
          59,
        ),
        policy: _policy,
        trackingState: SttEvidenceTrackingState.recovering,
        currentIndex: 36,
        advanceGuardIndex: 36,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );

      expect(decision.action, SttMovementAction.advance);
      expect(decision.reason, 'profile_visible_skip');
    });

    test('trusted visible local-recovery candidate waits for visible evidence',
        () {
      final decision = policy.evaluateCandidate(
        alignment: AlignmentResult(
          59,
          1.0,
          'LOCAL_RECOVERY_PHRASE',
          SttAlignmentDecision.advance,
          SttAlignmentKind.localRecoveryPhrase,
          SttThresholdFamily.safetyRecovery,
          const [57, 58],
          const ['special', 'conversation'],
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

      expect(decision.action, SttMovementAction.hold);
      expect(decision.reason, 'needs_more_visibleSkip');
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
      expect(luckyFutureWord.action, isNot(SttMovementAction.advance));
    });
  });
}
