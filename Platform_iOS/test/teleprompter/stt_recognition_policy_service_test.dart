import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_recognition_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Live transcript windowing', () {
    test('starts with a short suffix instead of a packed paragraph', () {
      const transcript =
          'both of them are good business people right. But that was like '
          'a black swan and it was very hard for them to get out of debt. '
          'and and i think that the most exciting thing for us was not the '
          'fact that we have gonna kill that much faster than they could '
          'ever ever imagine i think that the coolest part was';

      final windows =
          SttRecognitionPolicyService.liveTranscriptWindowsForAlignment(
        transcript,
        shortWindowWords: 10,
        longWindowWords: 18,
        maxWindows: 8,
      );

      expect(windows, isNotEmpty);
      expect(windows.first.split(RegExp(r'\s+')).length, lessThanOrEqualTo(10));
      expect(windows.first.toLowerCase(), isNot(contains('both of them')));
      expect(
        windows.any(
          (window) => window.toLowerCase().contains('both of them are good'),
        ),
        isTrue,
      );
      expect(
        windows.every((window) => window.split(RegExp(r'\s+')).length <= 18),
        isTrue,
      );
    });

    test('caps retained relock transcript to recent words', () {
      final transcript = List.generate(140, (index) => 'word$index').join(' ');

      final capped = SttRecognitionPolicyService.capTranscriptWords(
        transcript,
        maxWords: 24,
      );
      final words = capped.split(RegExp(r'\s+'));

      expect(words.length, 24);
      expect(words.first, 'word116');
      expect(words.last, 'word139');
    });
  });

  group('STT recognition profiles', () {
    test('manual profile uses exact threshold settings', () {
      final policy = SttRecognitionPolicyService.recognitionPolicyForSettings(
        const AppSettings(
          sttManualProfileEnabled: true,
          sttManualStartAdvanceSmallWords: 6,
          sttManualStartAdvanceBigWords: 4,
          sttManualSafetySmallWords: 3,
          sttManualSafetyBigWords: 2,
          sttManualVisibleSkipSmallWords: 7,
          sttManualVisibleSkipBigWords: 5,
          sttManualBigWordMinLetters: 6,
          sttVisibleSkipEnabled: true,
          sttHardVisibleSkipEnabled: true,
          sttStrictBulletMode: true,
        ),
      );

      expect(policy.bulletMode, isFalse);
      expect(policy.visibleSkipEnabled, isTrue);
      expect(policy.hardVisibleSkipEnabled, isFalse);
      expect(policy.startAdvance.label, '6 small / 4 big');
      expect(policy.safetyRecovery.label, '3 small / 2 big');
      expect(policy.visibleSkip.label, '7 small / 5 big');
      expect(policy.startAdvance.evidenceCost('premium'), 1.5);
    });

    test('manual visible skip stays off when either threshold is zero', () {
      final policy = SttRecognitionPolicyService.recognitionPolicyForSettings(
        const AppSettings(
          sttManualProfileEnabled: true,
          sttManualVisibleSkipSmallWords: 0,
          sttManualVisibleSkipBigWords: 4,
        ),
      );

      expect(policy.visibleSkipEnabled, isFalse);
    });

    test('no-progress policy never force-skips on iOS V5 profile stack', () {
      expect(
        SttRecognitionPolicyService.shouldForceSkipAfterNoProgress(
          strictBulletMode: false,
          noProgressCount: 100,
          skipThreshold: 45,
        ),
        isFalse,
      );
    });
  });
}
