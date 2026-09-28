import 'package:autoteleprompter/core/extensions/string_extensions.dart';
import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/spoken_number_normalizer.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_movement_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_recognition_policy_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_transcript_buffer_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_tracking_state.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_visible_skip_context_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptWord _word(String raw, int index) {
  return ScriptWord(
    raw: raw,
    normalized: raw.normalizeForMatching(),
    index: index,
    isRtl: raw.isHebrew,
  );
}

List<ScriptWord> _words(List<String> raw) => [
  for (var i = 0; i < raw.length; i++) _word(raw[i], i),
];

ScriptWord _newline(int index) => ScriptWord(
  raw: '\n',
  normalized: '',
  index: index,
  isRtl: false,
  isNewline: true,
);

const _numberPolicy = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: true,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(3, 2),
  safetyRecovery: SttEvidenceThreshold(2, 1),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

const _headingPolicy = SttRecognitionPolicy(
  bulletMode: false,
  visibleSkipEnabled: false,
  hardVisibleSkipEnabled: false,
  startAdvance: SttEvidenceThreshold(4, 3),
  safetyRecovery: SttEvidenceThreshold(3, 2),
  visibleSkip: SttEvidenceThreshold(4, 3),
);

void main() {
  group('digit script number', () {
    final script = _words([
      'נפגשים',
      'הוקמה',
      'בשנת',
      '2022,',
      'עוד',
      'לפני',
      'המלחמה.',
    ]);

    test('matches the immediate year when spoken in Hebrew', () {
      final result = WordAligner.align(
        script: script,
        transcript: 'אלפיים עשרים ושתיים',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 3, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
      expect(result.matchedScriptIndices, [3]);
    });

    test('consumes the number and continues into following Hebrew text', () {
      final result = WordAligner.align(
        script: script,
        transcript: 'אלפיים עשרים ושתיים עוד',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 4, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
      expect(result.matchedScriptIndices, [3, 4]);
    });

    test('matches English cardinal, year, and digit-sequence readings', () {
      for (final transcript in [
        'two thousand twenty two',
        'twenty twenty two',
        'two zero two two',
        '2022',
      ]) {
        final result = WordAligner.align(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 2,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(
          result.shouldAdvance,
          isTrue,
          reason: '$transcript: ${result.debugInfo}',
        );
        expect(result.confirmedWordIndex, 3, reason: transcript);
        expect(result.kind, SttAlignmentKind.numberPhrase, reason: transcript);
      }
    });

    test('matches colloquial Hebrew and digit-pair year readings', () {
      for (final transcript in ['עשרים עשרים ושתיים', '20 22']) {
        final result = WordAligner.align(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 2,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
        expect(result.confirmedWordIndex, 3, reason: transcript);
        expect(result.kind, SttAlignmentKind.numberPhrase, reason: transcript);
      }
    });

    test('does not treat conjunction-separated numbers as a year pair', () {
      for (final transcript in ['עשרים ועשרים ושתיים', 'עשרים ואפס חמש']) {
        final result = WordAligner.align(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 2,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
        expect(result.confirmedWordIndex, 2, reason: transcript);
      }
    });

    test('colloquial year pairs require an adjacent script year cue', () {
      final noYearCue = _words(['current', '2022', 'ending']);
      for (final transcript in ['עשרים עשרים ושתיים', '20 22']) {
        final result = WordAligner.align(
          script: noYearCue,
          transcript: transcript,
          lastConfirmedIndex: 0,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
        expect(result.confirmedWordIndex, 0);
      }
    });

    test('a rejected no-cue year pair cannot inflate generic evidence', () {
      final noYearCue = _words([
        'start',
        'filler',
        'filler',
        'filler',
        'current',
        '2022',
        'ending',
        'words',
      ]);
      final result = WordAligner.align(
        script: noYearCue,
        transcript: '20 22 ending words',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: noYearCue.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 0);
    });

    test('a wrong year does not advance through the displayed year', () {
      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty three',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 2, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });

    test('omitting displayed digits preserves the old skippable behavior', () {
      final result = WordAligner.align(
        script: script,
        transcript: 'עוד לפני',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
      expect(
        result.confirmedWordIndex,
        greaterThanOrEqualTo(4),
        reason: result.debugInfo,
      );
    });
  });

  group('number words in the script', () {
    test('literal digits consume the complete Hebrew number-word span', () {
      final script = _words([
        'נפגשים',
        'הוקמה',
        'בשנת',
        'אלפיים',
        'עשרים',
        'ושתיים',
        'עוד',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: '2022',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 5, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
      expect(result.matchedScriptIndices, [3, 4, 5]);
    });

    test('English speech matches a Hebrew number-word span', () {
      final script = _words([
        'נפגשים',
        'הוקמה',
        'בשנת',
        'אלפיים',
        'עשרים',
        'ושתיים',
        'עוד',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty two',
        lastConfirmedIndex: 2,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 5, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
    });

    test('Hebrew speech matches an English number-word span', () {
      final script = _words([
        'Meetings',
        'were',
        'founded',
        'in',
        'two',
        'thousand',
        'twenty-two',
        'before',
        'war.',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'אלפיים עשרים ושתיים',
        lastConfirmedIndex: 3,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 6, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
      expect(result.matchedScriptIndices, [4, 5, 6]);
    });
  });

  group('number jump safety', () {
    test('a number alone cannot jump to a distant visible occurrence', () {
      final script = _words([
        'start',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        '2022',
        'ending',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty two',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });

    test('repeated values select only the immediate continuation', () {
      final script = _words([
        'start',
        '2022',
        'alpha',
        'beta',
        'gamma',
        '2022',
        'ending',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'twenty twenty two',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 1, reason: result.debugInfo);
      expect(result.kind, SttAlignmentKind.numberPhrase);
    });

    test('a number alone cannot satisfy start-advance evidence', () {
      final script = _words(['2022', 'welcome', 'everyone']);

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty two',
        lastConfirmedIndex: -1,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, -1, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });

    test('unsafe time punctuation cannot masquerade as the year', () {
      final script = _words(['intro', '2022', 'outro']);

      final result = WordAligner.align(
        script: script,
        transcript: '20:22',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });

    test('leading-zero sequence does not equal the cardinal year', () {
      final script = _words(['intro', '2022', 'outro']);

      final result = WordAligner.align(
        script: script,
        transcript: '02022',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });
  });

  group('existing numbered-heading behavior', () {
    test(
      'still skips an unspoken numbered heading into matching body text',
      () {
        final script = _words([
          '1.',
          '-',
          'Opening',
          'Remarks',
          'Thank',
          'you,',
          'Naveh',
          'Dromi.',
        ]);

        final result = WordAligner.align(
          script: script,
          transcript: 'Thank you',
          lastConfirmedIndex: 0,
          policy: _headingPolicy,
        );

        expect(result.confirmedWordIndex, 5, reason: result.debugInfo);
        expect(result.kind, SttAlignmentKind.headingPrefixSkip);
      },
    );
  });

  group('reviewed number-context boundaries', () {
    test('a number match must reach the meaningful transcript tail', () {
      final script = _words(['intro', '2022', 'ending']);

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty two ending unrelated',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
    });

    test('number context cannot grow through a paragraph boundary', () {
      final script = <ScriptWord>[
        _word('intro', 0),
        _word('2022', 1),
        _newline(2),
        _word('after', 3),
      ];

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty two after',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
      expect(
        result.matchedScriptIndices,
        isNot(containsAllInOrder([1, 3])),
        reason: result.debugInfo,
      );
    });

    test(
      'strict mode rejects context accepted only by loose fuzzy matching',
      () {
        final script = _words(['intro', 'alpha', '2022', 'omega']);
        const transcript = 'alpo two thousand twenty two omega';

        final normal = WordAligner.align(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 0,
          readingStandby: true,
          policy: _numberPolicy,
        );
        final strict = WordAligner.align(
          script: script,
          transcript: transcript,
          lastConfirmedIndex: 0,
          maxSkipTargetIndex: script.length - 1,
          strictBulletMode: true,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(
          normal.kind,
          SttAlignmentKind.numberPhrase,
          reason: normal.debugInfo,
        );
        expect(strict.shouldAdvance, isFalse, reason: strict.debugInfo);
        expect(strict.confirmedWordIndex, 0, reason: strict.debugInfo);
        expect(strict.debugInfo, 'NUMBER_MATCH_REJECTED');
      },
    );

    test('wrong year plus exact lexical tail waits instead of skipping it', () {
      final script = _words(['intro', '2022', 'exact', 'lexical', 'tail']);

      final result = WordAligner.align(
        script: script,
        transcript: 'two thousand twenty three exact lexical tail',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
      expect(result.decision, SttAlignmentDecision.wait);
      expect(result.debugInfo, 'NUMBER_MATCH_REJECTED');
    });

    test(
      'stale number before a sentence boundary cannot freeze lexical tail',
      () {
        final script = _words([
          'current',
          'latest',
          'lexical',
          '2022',
          'future',
        ]);

        final result = WordAligner.align(
          script: script,
          transcript: 'old 2022. latest lexical',
          lastConfirmedIndex: 0,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
        expect(result.confirmedWordIndex, 2, reason: result.debugInfo);
        expect(result.debugInfo, isNot('NUMBER_MATCH_REJECTED'));
      },
    );

    test('stale number without punctuation cannot freeze lexical tail', () {
      final script = _words(['current', 'latest', 'lexical', '2022', 'future']);

      final result = WordAligner.align(
        script: script,
        transcript: 'old 2022 latest lexical',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isTrue, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 2, reason: result.debugInfo);
      expect(result.debugInfo, isNot('NUMBER_MATCH_REJECTED'));
    });

    test('ordinary conjunction contexts cannot block generic alignment', () {
      final cases = [
        (
          transcript: 'latest and lexical',
          phrase: <String>['latest', 'and', 'lexical'],
        ),
        (transcript: 'חדש ו מדויק', phrase: <String>['חדש', 'ו', 'מדויק']),
        (transcript: 'שנים טובות', phrase: <String>['שנים', 'טובות']),
        (transcript: 'ושנים טובות', phrase: <String>['ושנים', 'טובות']),
      ];

      for (final testCase in cases) {
        final script = _words([
          'current',
          ...testCase.phrase,
          '2022',
          'future',
        ]);
        final result = WordAligner.align(
          script: script,
          transcript: testCase.transcript,
          lastConfirmedIndex: 0,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(
          result.shouldAdvance,
          isTrue,
          reason: '${testCase.transcript}: ${result.debugInfo}',
        );
        expect(
          result.confirmedWordIndex,
          testCase.phrase.length,
          reason: '${testCase.transcript}: ${result.debugInfo}',
        );
        expect(
          result.debugInfo,
          isNot('NUMBER_MATCH_REJECTED'),
          reason: testCase.transcript,
        );
      }
    });
  });

  group('immediate number span cap and thresholds', () {
    final atCapScript = _words([
      'intro',
      'one',
      'hundred',
      'one',
      'million',
      'one',
      'hundred',
      'one',
      'thousand',
      'completion',
    ]);

    test('allows an eight-token number plus one immediate lexical tail', () {
      final alignment = WordAligner.align(
        script: atCapScript,
        transcript: '101101000 completion',
        lastConfirmedIndex: 0,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(alignment.kind, SttAlignmentKind.numberPhrase);
      expect(alignment.confirmedWordIndex, WordAligner.maxLocalNumberAdvance);
      expect(alignment.thresholdFamily, SttThresholdFamily.safetyRecovery);

      final movement = const SttMovementPolicyService().evaluateCandidate(
        alignment: alignment,
        policy: _numberPolicy,
        trackingState: SttEvidenceTrackingState.tracking,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted: false,
        maxLocalAdvanceWithoutWait: 2,
      );
      expect(movement.shouldAdvance, isTrue, reason: movement.debugSummary);
      expect(movement.targetIndex, WordAligner.maxLocalNumberAdvance);
    });

    test('a longer immediate tail must satisfy the visible threshold', () {
      final script = _words([
        ...atCapScript.map((word) => word.raw),
        'context',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: '101101000 completion context',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 1,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
    });
  });

  group('visible Hebrew number relock', () {
    test('advances to the real 2022 phrase and passes movement policy', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        'נפגשים',
        'הוקמה',
        'בשנת',
        '2022',
        'עוד',
        'לפני',
        'המלחמה',
      ]);

      final alignment = WordAligner.align(
        script: script,
        transcript: 'נפגשים הוקמה בשנת אלפיים עשרים ושתיים עוד לפני המלחמה',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(alignment.kind, SttAlignmentKind.numberPhrase);
      expect(alignment.thresholdFamily, SttThresholdFamily.visibleSkip);
      expect(alignment.candidateStartIndex, 6);
      expect(alignment.confirmedWordIndex, 12);

      final movement = const SttMovementPolicyService().evaluateCandidate(
        alignment: alignment,
        policy: _numberPolicy,
        trackingState: SttEvidenceTrackingState.recovering,
        currentIndex: 0,
        advanceGuardIndex: 0,
        visibleSkipTargetTrusted: true,
        maxLocalAdvanceWithoutWait: 2,
      );
      expect(movement.shouldAdvance, isTrue, reason: movement.debugSummary);
      expect(movement.targetIndex, 12);
      expect(movement.thresholdLabel, 'visibleSkip');
    });

    test('combines split browser shards into the colloquial 20 22 year', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        'נפגשים',
        'הוקמה',
        'בשנת',
        '2022',
        'עוד',
      ]);
      final rescue = const SttVisibleSkipContextService().rescueAlignment(
        script: script,
        pendingTranscript: 'נפגשים הוקמה בשנת 20',
        transcript: '22 עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        policy: _numberPolicy,
      );

      expect(rescue, isNotNull);
      expect(rescue!.kind, SttAlignmentKind.numberPhrase);
      expect(rescue.confirmedWordIndex, 10, reason: rescue.debugInfo);
      expect(rescue.matchedScriptIndices, [6, 7, 8, 9, 10]);
      expect(rescue.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת', 'num', 'עוד']);
    });

    test('preserves a repeated Hebrew twenty across browser shards', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        'נפגשים',
        'הוקמה',
        'בשנת',
        '2022',
        'עוד',
      ]);
      final rescue = const SttVisibleSkipContextService().rescueAlignment(
        script: script,
        pendingTranscript: 'נפגשים הוקמה בשנת עשרים',
        transcript: 'עשרים ושתיים עוד',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        policy: _numberPolicy,
      );

      expect(rescue, isNotNull);
      expect(rescue!.kind, SttAlignmentKind.numberPhrase);
      expect(rescue.confirmedWordIndex, 10, reason: rescue.debugInfo);
      expect(rescue.matchedScriptIndices, [6, 7, 8, 9, 10]);
      expect(rescue.evidenceWords, ['נפגשים', 'הוקמה', 'בשנת', 'num', 'עוד']);
    });

    test('visible slang cannot jump without matching its script year cue', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        'בשנת',
        '2022',
        'עוד',
        'לפני',
        'המלחמה',
        'עכשיו',
      ]);
      final result = WordAligner.align(
        script: script,
        transcript: '20 22 עוד לפני המלחמה עכשיו',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
      expect(result.confirmedWordIndex, 0);
    });

    test('equally supported repeated slang-year targets fail closed', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'epsilon',
        'בשנת',
        '2022',
        'עוד',
        'לפני',
        'separator',
        'בשנת',
        '2022',
        'עוד',
        'לפני',
      ]);
      final result = WordAligner.align(
        script: script,
        transcript: 'בשנת 20 22 עוד לפני',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
      expect(result.debugInfo, 'NUMBER_MATCH_REJECTED');
    });

    test('rejects context that begins before the visible start', () {
      final script = _words([
        'current',
        'alpha',
        'beta',
        'gamma',
        'delta',
        'hidden',
        '2022',
        'following',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'hidden two thousand twenty two following',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 6,
        maxSkipTargetIndex: script.length - 1,
        readingStandby: true,
        policy: _numberPolicy,
      );

      expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
      expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
    });
  });

  group('contextual numbered-heading markers', () {
    test(
      'parenthesized, colon, and separated-dash markers are not numbers',
      () {
        for (final raw in [
          ['(1)', 'Opening', 'Remarks'],
          ['1:', 'Opening', 'Remarks'],
          ['1', '-', 'Opening', 'Remarks'],
        ]) {
          final script = _words(raw);
          final result = WordAligner.align(
            script: script,
            transcript: 'one',
            lastConfirmedIndex: -1,
            readingStandby: true,
            policy: _numberPolicy,
          );

          expect(
            result.kind,
            isNot(SttAlignmentKind.numberPhrase),
            reason: '$raw',
          );
          expect(
            result.confirmedWordIndex,
            -1,
            reason: '$raw: ${result.debugInfo}',
          );
        }
      },
    );

    for (final marker in ['(1).', '1).']) {
      test('decorated heading $marker is not an immediate number anchor', () {
        final result = WordAligner.align(
          script: _words(['intro', marker, 'Opening']),
          transcript: 'one',
          lastConfirmedIndex: 0,
          readingStandby: true,
          policy: _numberPolicy,
        );

        expect(result.shouldAdvance, isFalse, reason: result.debugInfo);
        expect(result.confirmedWordIndex, 0, reason: result.debugInfo);
        expect(result.kind, isNot(SttAlignmentKind.numberPhrase));
      });
    }
  });

  group('structured-number transcript preservation', () {
    test('derived recognition windows keep 20:22 as one surface token', () {
      const transcript =
          'intro words before. meeting starts at 20:22 today. '
          'closing words continue now';
      final live =
          SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
            transcript,
            shortWindowWords: 4,
            mediumWindowWords: 6,
            longWindowWords: 8,
            maxWindows: 8,
          );
      final rolling =
          SttRecognitionPolicyService.rollingTranscriptWindowsForAlignment(
            transcript,
            windowWords: 6,
            maxWindows: 6,
          );

      expect(
        [...live, ...rolling].any((window) => window.contains('20:22')),
        isTrue,
      );
      expect([...live, ...rolling], everyElement(isNot(contains('20 22'))));
    });

    test('visible-skip transcript merge preserves the time punctuation', () {
      final merged = const SttVisibleSkipContextService()
          .mergePendingTranscript(
            pendingTranscript: 'meeting starts at 20:22',
            transcript: 'at 20:22 today',
          );

      expect(merged, 'meeting starts at 20:22 today');
      expect(merged, isNot(contains('20 22')));
    });

    test('buffer preserves spaced time and range separators', () {
      for (final structured in [
        '20 : 22',
        '20 - 22',
        '20 – 22',
        '20 — 22',
        '20 − 22',
        '20 ־ 22',
      ]) {
        final buffered = const SttTranscriptBufferService().update(
          rawTranscript: 'meeting at $structured now',
          transcriptFloor: 0,
        );

        expect(
          buffered.recentSurfaceTranscript,
          'meeting at $structured now',
          reason: structured,
        );
        expect(
          buffered.recentSurfaceTranscript,
          isNot(contains('20 22')),
          reason: structured,
        );
      }
    });

    test('visible-context merge preserves spaced structured separators', () {
      for (final structured in [
        '20 : 22',
        '20 - 22',
        '20 – 22',
        '20 — 22',
        '20 − 22',
        '20 ־ 22',
      ]) {
        final merged = const SttVisibleSkipContextService()
            .mergePendingTranscript(
              pendingTranscript: 'meeting starts at $structured',
              transcript: 'at $structured today',
            );

        expect(
          merged,
          'meeting starts at $structured today',
          reason: structured,
        );
        expect(merged, isNot(contains('20 22')), reason: structured);
      }
    });

    test('buffered spaced structure stays atomic in all derived windows', () {
      for (final separator in [':', '-']) {
        final buffered = const SttTranscriptBufferService().update(
          rawTranscript:
              'alpha bravo charlie delta echo meeting at '
              '20 $separator 22 today closing words continue now',
          transcriptFloor: 0,
          recentWordWindow: 40,
        );
        final live =
            SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
              buffered.recentSurfaceTranscript,
              shortWindowWords: 4,
              mediumWindowWords: 6,
              longWindowWords: 8,
              maxWindows: 12,
            );
        final rolling =
            SttRecognitionPolicyService.rollingTranscriptWindowsForAlignment(
              buffered.recentSurfaceTranscript,
              windowWords: 4,
              maxWindows: 12,
            );
        final windows = {...live, ...rolling};
        var touchingWindows = 0;

        for (final window in windows) {
          final surfaces = SpokenNumberNormalizer.surfaceTokens(window);
          final touchesStructure = surfaces.any(
            (word) => word == '20' || word == separator || word == '22',
          );
          if (touchesStructure) {
            touchingWindows++;
            expect(window, contains('20 $separator 22'), reason: window);
          }
          expect(
            SpokenNumberNormalizer.scan(surfaces),
            isEmpty,
            reason: '$separator window: $window',
          );
        }

        expect(touchingWindows, greaterThan(0), reason: separator);
      }
    });

    test('sentence cutoff on right-hand 22 keeps the full spaced time', () {
      const structure = '20 : 22';
      const transcript =
          'alpha bravo charlie delta echo $structure tail closing final';
      final windows =
          SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
            transcript,
            shortWindowWords: 4,
            mediumWindowWords: 4,
            longWindowWords: 4,
            maxWindows: 12,
          );
      final touching = windows
          .where((window) {
            final surfaces = SpokenNumberNormalizer.surfaceTokens(window);
            return surfaces.contains('20') || surfaces.contains('22');
          })
          .toList(growable: false);

      expect(touching, isNotEmpty);
      for (final window in touching) {
        expect(window, contains(structure), reason: window);
        expect(
          SpokenNumberNormalizer.scan(
            SpokenNumberNormalizer.surfaceTokens(window),
          ),
          isEmpty,
          reason: window,
        );
      }
    });

    test('word-number structures cannot expose a clean right-side window', () {
      final cases = [
        (
          transcript: 'alpha bravo twenty : twenty two tail closing',
          structure: 'twenty : twenty two',
          numericWords: <String>{'twenty', 'two'},
        ),
        (
          transcript: 'alpha bravo one hundred : twenty two tail closing',
          structure: 'one hundred : twenty two',
          numericWords: <String>{'one', 'hundred', 'twenty', 'two'},
        ),
        (
          transcript: 'alpha bravo one thousand : twenty two tail closing',
          structure: 'one thousand : twenty two',
          numericWords: <String>{'one', 'thousand', 'twenty', 'two'},
        ),
        (
          transcript: 'פתיחה נוספת עשרים : עשרים ושתיים סיום אחרון',
          structure: 'עשרים : עשרים ושתיים',
          numericWords: <String>{'עשרים', 'ושתיים'},
        ),
      ];

      for (final testCase in cases) {
        final windows =
            SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
              testCase.transcript,
              shortWindowWords: 4,
              mediumWindowWords: 4,
              longWindowWords: 4,
              maxWindows: 12,
            );
        final touching = windows
            .where((window) {
              final surfaces = SpokenNumberNormalizer.surfaceTokens(window);
              return surfaces.any(testCase.numericWords.contains);
            })
            .toList(growable: false);

        expect(touching, isNotEmpty, reason: testCase.transcript);
        for (final window in touching) {
          expect(window, contains(testCase.structure), reason: window);
          expect(
            SpokenNumberNormalizer.scan(
              SpokenNumberNormalizer.surfaceTokens(window),
            ),
            isEmpty,
            reason: window,
          );
        }
      }
    });

    test('nonzero floor retains unsafe structure after consumed old words', () {
      for (final separator in [':', '/', '-', '–', '—', '−', '־']) {
        final buffered = const SttTranscriptBufferService().update(
          rawTranscript: 'old 20 $separator 22 latest',
          transcriptFloor: 2,
        );

        expect(buffered.transcriptFloor, 2, reason: separator);
        expect(
          buffered.recentSurfaceTranscript,
          '$separator 22 latest',
          reason: separator,
        );
        expect(
          buffered.recentSurfaceTranscript,
          isNot('22 latest'),
          reason: separator,
        );
        expect(
          buffered.recentSurfaceTranscript,
          isNot(contains('20 22')),
          reason: separator,
        );
      }
    });
  });
}
