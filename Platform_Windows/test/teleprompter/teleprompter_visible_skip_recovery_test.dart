// October 6 regression: elapsed stall time must never make off-screen text
// visible/trusted or invalidate pending evidence for an unchanged viewport.
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_tracking_state.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: true,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(3, 2),
  safetyRecovery: SttEvidenceThreshold(2, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

void main() {
  group('resolveVisibleSkipTarget', () {
    test('stays capped at the rendered viewport when not sustained-stuck', () {
      final target = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 20,
        visibleWordEnd: 30,
        scriptWordCount: 200,
        sustainedStuck: false,
      );
      expect(target, 30);
    });

    test('stays inside the viewport even when sustained-stuck', () {
      final target = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 20,
        visibleWordEnd: 30,
        scriptWordCount: 200,
        sustainedStuck: true,
      );
      expect(target, 30);
    });

    test('elapsed stall time cannot change a saved recovery boundary', () {
      final target = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 20,
        visibleWordEnd: 30,
        scriptWordCount: 200,
        sustainedStuck: true,
      );
      // Pending fragments store the actual end (30). A widened search end
      // causes _maybeAdvancePendingVisibleSkip to clear them on every result.
      const pendingVisibleEnd = 30;
      expect(target, pendingVisibleEnd);
    });

    test('never exceeds the end of the script', () {
      final target = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 20,
        visibleWordEnd: 30,
        scriptWordCount: 35,
        sustainedStuck: true,
      );
      expect(target, lessThanOrEqualTo(34));
    });

    test(
      'disabled visible skip still returns null regardless of stuck state',
      () {
        final target = TeleprompterNotifier.resolveVisibleSkipTarget(
          visibleSkipEnabled: false,
          strictBulletMode: false,
          visibleWordStart: 20,
          visibleWordEnd: 30,
          scriptWordCount: 200,
          sustainedStuck: true,
        );
        expect(target, isNull);
      },
    );
  });

  group('isTrustedVisibleSkipTarget', () {
    for (final bounds in [(null, 30), (20, null), (-1, 30), (30, 20)]) {
      test('invalid bounds $bounds fail closed', () {
        expect(
          TeleprompterNotifier.resolveVisibleSkipTarget(
            visibleSkipEnabled: true,
            strictBulletMode: false,
            visibleWordStart: bounds.$1,
            visibleWordEnd: bounds.$2,
            sustainedStuck: true,
            scriptWordCount: 200,
          ),
          isNull,
        );
        expect(
          TeleprompterNotifier.isTrustedVisibleSkipTarget(
            alignedIndex: 25,
            visibleWordStart: bounds.$1,
            visibleWordEnd: bounds.$2,
          ),
          isFalse,
        );
      });
    }

    test('script bounds cannot create an artificial visible range', () {
      for (final count in [0, 10, 20]) {
        expect(
          TeleprompterNotifier.resolveVisibleSkipTarget(
            visibleSkipEnabled: true,
            strictBulletMode: false,
            visibleWordStart: 20,
            visibleWordEnd: 30,
            scriptWordCount: count,
          ),
          isNull,
        );
      }
      expect(
        TeleprompterNotifier.resolveVisibleSkipTarget(
          visibleSkipEnabled: true,
          strictBulletMode: false,
          visibleWordStart: 20,
          visibleWordEnd: 30,
          scriptWordCount: 25,
        ),
        24,
      );
    });

    test('a target beyond the raw viewport is untrusted when not stuck', () {
      const rawViewportEnd = 30;
      final trusted = TeleprompterNotifier.isTrustedVisibleSkipTarget(
        alignedIndex: 45,
        visibleWordStart: 20,
        visibleWordEnd: rawViewportEnd,
      );
      expect(trusted, isFalse);
    });

    test('an offscreen target stays untrusted after sustained stall', () {
      final widenedEnd = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 20,
        visibleWordEnd: 30,
        scriptWordCount: 200,
        sustainedStuck: true,
      );
      final trusted = TeleprompterNotifier.isTrustedVisibleSkipTarget(
        alignedIndex: 45,
        visibleWordStart: 20,
        visibleWordEnd: widenedEnd,
      );
      expect(trusted, isFalse);
    });
  });

  group('visible recovery through actual aligner and movement policy', () {
    final script = WordAligner.tokenize(
      [
        ...List.filled(25, 'placeholder'),
        'הספרייה נפתחה בשנת 2022 כאן ליד התחנה',
        ...List.filled(45, 'placeholder'),
      ].join(' '),
    );

    SttMovementDecision evaluate({required int visibleEnd, String? heard}) {
      final end = TeleprompterNotifier.resolveVisibleSkipTarget(
        visibleSkipEnabled: true,
        strictBulletMode: false,
        visibleWordStart: 0,
        visibleWordEnd: visibleEnd,
        scriptWordCount: script.length,
        sustainedStuck: true,
      );
      final aligned = WordAligner.align(
        script: script,
        transcript: heard ?? 'הספרייה נפתחה בשנת 2022 כאן ליד התחנה',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 0,
        maxSkipTargetIndex: end,
        readingStandby: true,
        policy: _profile,
      );
      return const SttMovementPolicyService().evaluateCandidate(
        alignment: aligned,
        policy: _profile,
        trackingState: SttEvidenceTrackingState.offScript,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted:
            TeleprompterNotifier.isTrustedVisibleSkipTarget(
              alignedIndex: aligned.confirmedWordIndex,
              visibleWordStart: 0,
              visibleWordEnd: end,
            ),
        maxLocalAdvanceWithoutWait: 2,
      );
    }

    test('strong Hebrew evidence cannot recover to hidden words', () {
      final decision = evaluate(visibleEnd: 20);
      expect(decision.shouldAdvance, isFalse, reason: decision.debugSummary);
    });

    test('the same phrase can recover after it becomes visible', () {
      final decision = evaluate(visibleEnd: 31);
      expect(decision.shouldAdvance, isTrue, reason: decision.debugSummary);
      expect(decision.targetIndex, inInclusiveRange(25, 31));
    });

    test('partial evidence still respects the unchanged profile', () {
      final decision = evaluate(visibleEnd: 31, heard: 'הספרייה נפתחה');
      expect(decision.shouldAdvance, isFalse, reason: decision.debugSummary);
    });
  });

  group('pending visible-skip context lifetime', () {
    final now = DateTime.utc(2026, 9, 25, 12);

    test('keeps a recent browser shard', () {
      expect(
        TeleprompterNotifier.isPendingVisibleSkipExpired(
          startedAt: now.subtract(const Duration(seconds: 7)),
          now: now,
        ),
        isFalse,
      );
    });

    test('expires stale speech so it cannot cross unrelated attempts', () {
      expect(
        TeleprompterNotifier.isPendingVisibleSkipExpired(
          startedAt: now.subtract(const Duration(seconds: 9)),
          now: now,
        ),
        isTrue,
      );
    });

    test('does not expire when no fragment is pending', () {
      expect(
        TeleprompterNotifier.isPendingVisibleSkipExpired(
          startedAt: null,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
