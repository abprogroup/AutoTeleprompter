import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

const _hOpening = '\u05e4\u05ea\u05d9\u05d7\u05d4';
const _hBlessing = '\u05d1\u05e8\u05db\u05d4';
const _hClosing = '\u05e1\u05d9\u05d5\u05dd';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

List<ScriptWord> _words(List<String> raw) {
  return [
    for (var i = 0; i < raw.length; i++) _word(raw[i], i),
  ];
}

void main() {
  group('Windows v5 STT recognition policy', () {
    test('evidence thresholds use small and big word weights', () {
      expect(
        const SttEvidenceThreshold(4).passes(['one', 'two', 'red', 'sun']),
        isTrue,
      );
      expect(
        const SttEvidenceThreshold(4).passes(['alpha', 'bravo', 'delta']),
        isTrue,
      );
      expect(
        const SttEvidenceThreshold(4).passes(['one', 'two', 'red']),
        isFalse,
      );
      expect(const SttEvidenceThreshold(2).passes(['alpha']), isTrue);
      expect(
        const SttEvidenceThreshold(2).passes(['one', 'two']),
        isTrue,
      );
      expect(
        const SttEvidenceThreshold(5).passes(['one', 'two', 'red', 'sun']),
        isFalse,
      );
      expect(
        const SttEvidenceThreshold(5)
            .passes(['alpha', 'bravo', 'delta', 'gamma']),
        isTrue,
      );
    });

    test('normal mode does not advance from one or two unlocked words', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma', 'delta']);

      final oneWord = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
      );
      final twoWords = WordAligner.align(
        script: script,
        transcript: 'alpha beta',
        lastConfirmedIndex: 0,
      );

      expect(oneWord.confirmedWordIndex, 0);
      expect(oneWord.decision, SttAlignmentDecision.wait);
      expect(twoWords.confirmedWordIndex, 0);
      expect(twoWords.decision, SttAlignmentDecision.standby);
    });

    test('normal mode advances after the start threshold is met', () {
      final script = _words(['intro', 'one', 'two', 'red', 'sun']);

      final result = WordAligner.align(
        script: script,
        transcript: 'one two red sun',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 4);
      expect(result.decision, SttAlignmentDecision.advance);
    });

    test('normal standby allows local recovery with one big word', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma']);

      final result = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
        readingStandby: true,
      );

      expect(result.confirmedWordIndex, 1);
      expect(result.decision, SttAlignmentDecision.advance);
    });

    test('normal off-script speech breaks standby without force-skip', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma']);

      final result = WordAligner.align(
        script: script,
        transcript: 'unrelated improvisation',
        lastConfirmedIndex: 0,
        readingStandby: true,
      );

      expect(result.confirmedWordIndex, 0);
      expect(result.decision, SttAlignmentDecision.wait);
      expect(
        TeleprompterNotifier.shouldForceSkipAfterNoProgress(
          strictBulletMode: false,
          noProgressCount: 100,
          skipThreshold: 45,
        ),
        isFalse,
      );
    });

    test('bullet mode requires two big words or three small words', () {
      final script = _words(['intro', 'alpha', 'bravo', 'one', 'two', 'red']);

      final singleBig = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );
      final twoBig = WordAligner.align(
        script: script,
        transcript: 'alpha bravo',
        lastConfirmedIndex: 0,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );
      final threeSmall = WordAligner.align(
        script: script,
        transcript: 'one two red',
        lastConfirmedIndex: 2,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );

      expect(singleBig.confirmedWordIndex, 0);
      expect(singleBig.decision, SttAlignmentDecision.wait);
      expect(twoBig.confirmedWordIndex, 2);
      expect(twoBig.decision, SttAlignmentDecision.advance);
      expect(threeSmall.confirmedWordIndex, 5);
      expect(threeSmall.decision, SttAlignmentDecision.advance);
    });

    test('bullet mode treats unrelated words as listen-and-wait', () {
      final script = _words(['intro', 'alpha', 'bravo', 'charlie']);

      final result = WordAligner.align(
        script: script,
        transcript: 'unrelated words',
        lastConfirmedIndex: 0,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );

      expect(result.confirmedWordIndex, 0);
      expect(result.decision, SttAlignmentDecision.wait);
    });

    test('bullet mode can relock to a visible Hebrew phrase', () {
      final script = [
        _word('intro', 0),
        _word(_hOpening, 1, rtl: true),
        _word(_hBlessing, 2, rtl: true),
        _word(_hClosing, 3, rtl: true),
      ];

      final result = WordAligner.align(
        script: script,
        transcript: '$_hOpening $_hBlessing $_hClosing',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: 3,
        policy: SttRecognitionPolicy.legacy(
          strictBulletMode: true,
          visibleSkipEnabled: true,
        ),
      );

      expect(result.confirmedWordIndex, 3);
      expect(result.decision, SttAlignmentDecision.advance);
    });

    test('strict bullet no longer enables visible skip by itself', () {
      expect(
        TeleprompterNotifier.resolveVisibleSkipTarget(
          visibleSkipEnabled: false,
          strictBulletMode: true,
          visibleWordStart: 10,
          visibleWordEnd: 40,
        ),
        isNull,
      );
    });

    test('manual profile overrides mode buttons with custom thresholds', () {
      const settings = AppSettings(
        sttManualProfileEnabled: true,
        sttStrictBulletMode: true,
        sttVisibleSkipEnabled: true,
        sttHardVisibleSkipEnabled: true,
        sttManualStartAdvanceSmallWords: 6,
        sttManualSafetySmallWords: 3,
        sttManualVisibleSkipSmallWords: 0,
      );

      final policy = TeleprompterNotifier.recognitionPolicyForSettings(
        settings,
      );

      expect(policy.bulletMode, isFalse);
      expect(policy.visibleSkipEnabled, isFalse);
      expect(policy.hardVisibleSkipEnabled, isFalse);
      expect(policy.startAdvance.smallWords, 6);
      expect(policy.safetyRecovery.smallWords, 3);
    });

    test('strict improvisation still caps the visible-assist wait counter', () {
      expect(
        TeleprompterNotifier.nextNoProgressCount(
          currentCount: 20,
          improvising: true,
          visibleAssistThreshold: 2,
        ),
        2,
      );
    });
  });
}
