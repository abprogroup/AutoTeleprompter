import 'package:autoteleprompter/core/extensions/string_extensions.dart';
import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_tracking_state.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_visible_skip_context_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptWord _word(String raw, int index) => ScriptWord(
  raw: raw,
  normalized: raw.normalizeForMatching(),
  index: index,
  isRtl: raw.isHebrew,
);

List<ScriptWord> _words(List<String> raw) => [
  for (var i = 0; i < raw.length; i++) _word(raw[i], i),
];

const _userPolicy = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: true,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(4, 3),
  safetyRecovery: SttEvidenceThreshold(1, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

final _reportedScript = _words([
  'current',
  'alpha',
  'beta',
  'gamma',
  'delta',
  'epsilon',
  'נפגשים',
  'הוקמה',
  'בשנת',
  '2022,',
  'עוד',
  'לפני',
  'המלחמה.',
]);

AlignmentResult _align(String transcript, {SttRecognitionPolicy? policy}) =>
    WordAligner.align(
      script: _reportedScript,
      transcript: transcript,
      lastConfirmedIndex: 0,
      visibleSkipStartIndex: 6,
      maxSkipTargetIndex: _reportedScript.length - 1,
      readingStandby: true,
      policy: policy ?? _userPolicy,
    );

SttMovementDecision _movement(
  AlignmentResult alignment, {
  SttRecognitionPolicy policy = _userPolicy,
}) => const SttMovementPolicyService().evaluateCandidate(
  alignment: alignment,
  policy: policy,
  trackingState: SttEvidenceTrackingState.offScript,
  currentIndex: 0,
  advanceGuardIndex: 0,
  visibleSkipTargetTrusted: true,
  maxLocalAdvanceWithoutWait: 2,
);

void main() {
  group('bounded wrong-number safety recovery', () {
    test('wrong number at the tail holds and preserves matched prefix', () {
      final alignment = _align('נפגשים הוקמה בשנת 2000');

      expect(
        alignment.kind,
        SttAlignmentKind.numberMismatchRecovery,
        reason: alignment.debugInfo,
      );
      expect(alignment.confirmedWordIndex, 8, reason: alignment.debugInfo);
      expect(alignment.thresholdFamily, SttThresholdFamily.visibleSkip);
      expect(alignment.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת']);
      expect(alignment.evidenceWords, isNot(contains('2000')));

      final decision = _movement(alignment);
      expect(decision.shouldAdvance, isFalse, reason: decision.debugSummary);
      expect(decision.reason, 'needs_more_visibleSkip');
      expect(decision.evidenceScore, closeTo(11 / 3, 0.01));
      expect(decision.neededScore, 4);
    });

    test('one ordered word after the wrong number completes recovery', () {
      final alignment = _align('נפגשים הוקמה בשנת 2000 עוד');

      expect(
        alignment.kind,
        SttAlignmentKind.numberMismatchRecovery,
        reason: alignment.debugInfo,
      );
      expect(alignment.confirmedWordIndex, 10, reason: alignment.debugInfo);
      expect(alignment.matchedScriptIndices, [6, 7, 8, 10]);
      expect(alignment.matchedScriptIndices, isNot(contains(9)));
      expect(alignment.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת', 'עוד']);
      expect(alignment.evidenceWords, isNot(contains('2000')));

      final decision = _movement(alignment);
      expect(decision.shouldAdvance, isTrue, reason: decision.debugSummary);
      expect(decision.targetIndex, 10);
      expect(decision.thresholdLabel, 'visibleSkip');
      expect(decision.evidenceScore, greaterThan(4));

      final untrusted = const SttMovementPolicyService().evaluateCandidate(
        alignment: alignment,
        policy: _userPolicy,
        trackingState: SttEvidenceTrackingState.offScript,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted: false,
        maxLocalAdvanceWithoutWait: 2,
      );
      expect(untrusted.shouldBlock, isTrue);
      expect(untrusted.reason, 'visible_target_untrusted');
    });

    test(
      'a wrong colloquial year pair uses recovery, never exact matching',
      () {
        final alignment = _align('נפגשים הוקמה בשנת 20 23 עוד');

        expect(
          alignment.kind,
          SttAlignmentKind.numberMismatchRecovery,
          reason: alignment.debugInfo,
        );
        expect(alignment.confirmedWordIndex, 10, reason: alignment.debugInfo);
        expect(alignment.matchedScriptIndices, [6, 7, 8, 10]);
        expect(alignment.matchedScriptIndices, isNot(contains(9)));
        expect(_movement(alignment).shouldAdvance, isTrue);
      },
    );

    test('nearby mismatch still requires both visible and safety gates', () {
      final nearScript = _words([
        'current',
        'נפגשים',
        'הוקמה',
        'בשנת',
        '2022,',
        'עוד',
      ]);
      AlignmentResult alignNear(String transcript) => WordAligner.align(
        script: nearScript,
        transcript: transcript,
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: nearScript.length - 1,
        readingStandby: true,
        policy: _userPolicy,
      );

      final pending = alignNear('נפגשים הוקמה בשנת 2000');
      expect(pending.kind, SttAlignmentKind.numberMismatchRecovery);
      expect(pending.thresholdFamily, SttThresholdFamily.visibleSkip);
      expect(_movement(pending).shouldAdvance, isFalse);
      expect(_movement(pending).reason, 'needs_more_visibleSkip');

      const context = SttVisibleSkipContextService();
      final recovered = context.rescueAlignment(
        script: nearScript,
        pendingTranscript: 'נפגשים הוקמה בשנת 2000',
        transcript: 'עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: nearScript.length - 1,
        policy: _userPolicy,
      );
      expect(recovered, isNotNull);
      expect(recovered!.thresholdFamily, SttThresholdFamily.visibleSkip);
      expect(_movement(recovered).shouldAdvance, isTrue);
      expect(recovered.confirmedWordIndex, 5);
    });

    test('separate browser shards recover without counting the number', () {
      const context = SttVisibleSkipContextService();
      final rescue = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: 'נפגשים הוקמה בשנת 2000',
        transcript: 'עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );

      expect(rescue, isNotNull);
      expect(rescue!.kind, SttAlignmentKind.numberMismatchRecovery);
      expect(rescue.confirmedWordIndex, 10, reason: rescue.debugInfo);
      expect(rescue.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת', 'עוד']);
      expect(_movement(rescue).shouldAdvance, isTrue);
    });

    test('the reported weak browser shards are preserved and recovered', () {
      const context = SttVisibleSkipContextService();

      final firstShard = context.fragmentedYearPreservationAlignment(
        script: _reportedScript,
        transcript: 'נפגשים',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(firstShard, isNotNull);
      expect(firstShard!.evidenceWords, ['נפגשים']);

      var pending = context.mergePendingTranscript(
        pendingTranscript: 'נפגשים',
        transcript: 'בשנת 20',
      );
      final numberShard = context.fragmentedYearPreservationAlignment(
        script: _reportedScript,
        transcript: pending,
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(numberShard, isNotNull);
      expect(numberShard!.evidenceWords, ['נפגשים', 'בשנת']);
      expect(numberShard.evidenceWords, isNot(contains('20')));

      pending = context.mergePendingTranscript(
        pendingTranscript: pending,
        transcript: '20',
      );
      expect(pending, 'נפגשים בשנת 20');

      final tooEarly = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: pending,
        transcript: 'עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(tooEarly, isNull);

      final recovered = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: pending,
        transcript: 'עוד לפני',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(recovered, isNotNull);
      expect(recovered!.kind, SttAlignmentKind.numberMismatchRecovery);
      expect(recovered.confirmedWordIndex, 11, reason: recovered.debugInfo);
      expect(
        recovered.matchedScriptIndices,
        [6, 8, 10, 11],
        reason: '${recovered.evidenceWords} | ${recovered.debugInfo}',
      );
      expect(recovered.evidenceWords, ['נפגשים', 'בשנת', 'עוד', 'לפני']);
      expect(recovered.evidenceWords, isNot(contains('20')));
      expect(_movement(recovered).shouldAdvance, isTrue);
    });

    test('a weak cue-first shard needs enough later profile evidence', () {
      const context = SttVisibleSkipContextService();
      final preservation = context.fragmentedYearPreservationAlignment(
        script: _reportedScript,
        transcript: 'בשנת 20',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(preservation, isNotNull);
      expect(preservation!.evidenceWords, ['בשנת']);

      final tooEarly = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: 'בשנת 20',
        transcript: 'עוד לפני',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(tooEarly, isNull);

      final recovered = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: 'בשנת 20',
        transcript: 'עוד לפני המלחמה',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(recovered, isNotNull);
      expect(_movement(recovered!).shouldAdvance, isTrue);
      expect(recovered.evidenceWords, ['בשנת', 'עוד', 'לפני', 'המלחמה']);
    });

    test(
      'fragment preservation fails closed outside one visible year path',
      () {
        const context = SttVisibleSkipContextService();

        AlignmentResult? preserve(
          List<ScriptWord> script,
          String transcript, {
          int visibleStart = 1,
        }) => context.fragmentedYearPreservationAlignment(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 0,
          visibleSkipStartIndex: visibleStart,
          maxSkipTargetIndex: script.length - 1,
          policy: _userPolicy,
        );

        expect(preserve(_reportedScript, 'עוד'), isNull);
        expect(
          preserve(_reportedScript, 'בשנת 20:22', visibleStart: 6),
          isNull,
        );
        expect(
          preserve(_reportedScript, 'בשנת 20-22', visibleStart: 6),
          isNull,
        );
        expect(
          preserve(_reportedScript, 'בשנת 20/22', visibleStart: 6),
          isNull,
        );
        expect(preserve(_reportedScript, 'בשנת 20', visibleStart: 10), isNull);

        final noYearCue = _words(['current', 'נפגשים', 'הוקמה', '2022', 'עוד']);
        expect(preserve(noYearCue, 'נפגשים 20'), isNull);

        final ambiguous = _words([
          'current',
          'נפגשים',
          'בשנת',
          '2022',
          'עוד',
          'separator',
          'נפגשים',
          'בשנת',
          '2023',
          'עוד',
        ]);
        expect(preserve(ambiguous, 'נפגשים בשנת 20'), isNull);
      },
    );

    test('a numeric correction shard replaces the pending numeric tail', () {
      const context = SttVisibleSkipContextService();

      final merged = context.mergePendingTranscript(
        pendingTranscript: 'נפגשים הוקמה בשנת 2000',
        transcript: '20',
      );

      expect(merged, 'נפגשים הוקמה בשנת 20');
      expect(merged, isNot(contains('2000 20')));

      final preservation = context.preservationAlignment(
        script: _reportedScript,
        transcript: merged,
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(preservation, isNotNull);
      expect(preservation!.kind, SttAlignmentKind.numberMismatchRecovery);
      expect(preservation.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת']);
      expect(preservation.evidenceWords, isNot(contains('20')));
    });

    test('an unrelated numeric shard is appended and remains blocked', () {
      const context = SttVisibleSkipContextService();
      final merged = context.mergePendingTranscript(
        pendingTranscript: 'נפגשים הוקמה בשנת 2000',
        transcript: '7',
      );

      expect(merged, 'נפגשים הוקמה בשנת 2000 7');
      final rescue = context.rescueAlignment(
        script: _reportedScript,
        pendingTranscript: merged,
        transcript: 'עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: _reportedScript.length - 1,
        policy: _userPolicy,
      );
      expect(rescue, isNull);
    });

    test('tail-only wrong-number context remains blocked', () {
      final alignment = _align('2000 עוד לפני המלחמה');

      expect(alignment.shouldAdvance, isFalse, reason: alignment.debugInfo);
      expect(alignment.confirmedWordIndex, 0);
      expect(alignment.debugInfo, 'NUMBER_MATCH_REJECTED');
    });

    test('two wrong numbers cannot open the recovery bridge', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'prefix',
        '2022',
        'middle',
        '2023',
        'tail',
      ]);
      final alignment = WordAligner.align(
        script: script,
        transcript: 'prefix 2000 middle 2001 tail',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 5,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _userPolicy,
      );

      expect(alignment.shouldAdvance, isFalse, reason: alignment.debugInfo);
      expect(alignment.kind, isNot(SttAlignmentKind.numberMismatchRecovery));
    });

    test('ambiguous repeated wrong-number context remains blocked', () {
      final script = _words([
        'current',
        'פתיח',
        'הוקמה',
        'בשנת',
        '2022',
        'עוד',
        'separator',
        'פתיח',
        'הוקמה',
        'בשנת',
        '2023',
        'עוד',
      ]);
      final alignment = WordAligner.align(
        script: script,
        transcript: 'פתיח הוקמה בשנת 2000 עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _userPolicy,
      );

      expect(alignment.shouldAdvance, isFalse, reason: alignment.debugInfo);
      expect(alignment.debugInfo, 'NUMBER_MATCH_REJECTED');
    });

    test('a stricter safety profile waits for its full suffix evidence', () {
      const safetyTwo = SttRecognitionPolicy(
        bulletMode: false,
        visibleSkipEnabled: true,
        hardVisibleSkipEnabled: false,
        startAdvance: SttEvidenceThreshold(4, 3),
        safetyRecovery: SttEvidenceThreshold(2, 2),
        visibleSkip: SttEvidenceThreshold(4, 3),
      );
      final oneTailWord = _align(
        'נפגשים הוקמה בשנת 2000 עוד',
        policy: safetyTwo,
      );
      final twoTailWords = _align(
        'נפגשים הוקמה בשנת 2000 עוד לפני',
        policy: safetyTwo,
      );

      expect(oneTailWord.confirmedWordIndex, 8);
      expect(_movement(oneTailWord, policy: safetyTwo).shouldAdvance, isFalse);
      expect(twoTailWords.confirmedWordIndex, 11);
      expect(_movement(twoTailWords, policy: safetyTwo).shouldAdvance, isTrue);
    });

    test('an exact year still uses the exact number path', () {
      final alignment = _align('נפגשים הוקמה בשנת 2022 עוד');

      expect(alignment.kind, SttAlignmentKind.numberPhrase);
      expect(alignment.confirmedWordIndex, 10, reason: alignment.debugInfo);
      expect(_movement(alignment).shouldAdvance, isTrue);
    });
  });
}
