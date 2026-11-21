import 'package:autoteleprompter/features/teleprompter/services/stt_visible_skip_context_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const blessingScript = '''
אחד העובדים מברך את הברכות:
בָּרוּךְ אַתָּה ה' אֱלֹהֵינוּ מֶלֶךְ הָעוֹלָם, אֲשֶׁר קִדְּשָׁנוּ בְּמִצְוֹתָיו וְצִוָּנוּ לְהַדְלִיק נֵר חֲנֻכָּה.
בָּרוּךְ אַתָּה ה' אֱלֹהֵינוּ מֶלֶךְ הָעוֹלָם, שֶׁעָשָׂה נִסִּים לַאֲבוֹתֵינוּ בַּיָּמִים הָהֵם בַּזְּמַן הַזֶּה.
''';

  const policy = SttRecognitionPolicy(
    bulletMode: false,
    visibleSkipEnabled: true,
    hardVisibleSkipEnabled: false,
    startAdvance: SttEvidenceThreshold(4, 3),
    safetyRecovery: SttEvidenceThreshold(2, 1),
    bulletAdvance: SttEvidenceThreshold(4, 3),
    visibleSkip: SttEvidenceThreshold(4, 3),
  );

  group('Stage 1C — Live Hanukkah blessing log replay STT fixes', () {
    test(
      'matches Hebrew divine name abbreviation ה\' when speaker says אדוני and advances on visible skip',
      () {
        final words = WordAligner.tokenize(blessingScript);
        final oneIndex = words.indexWhere((w) => w.raw == 'אחד');
        final worldIndex = words.indexWhere((w) => w.raw.contains('הָעוֹלָם'));
        expect(oneIndex, greaterThanOrEqualTo(0));
        expect(worldIndex, greaterThan(oneIndex));

        final aligned = WordAligner.align(
          script: words,
          transcript: 'ברוך אתה אדוני אלוהינו מלך העולם',
          lastConfirmedIndex: oneIndex,
          visibleSkipStartIndex: 0,
          maxSkipTargetIndex: words.length - 1,
          policy: policy,
          readingStandby: false,
        );

        expect(aligned.shouldAdvance, isTrue);
        expect(aligned.confirmedWordIndex, worldIndex);
        expect(policy.visibleSkip.passes(aligned.evidenceWords), isTrue);
      },
    );

    test(
      'bridges one interior STT mishearing (פסטיבל for וציוונו) when real matched words clear 4.0',
      () {
        final words = WordAligner.tokenize(blessingScript);
        final oneIndex = words.indexWhere((w) => w.raw == 'אחד');
        final hanukkahIndex = words.indexWhere((w) => w.raw.contains('חֲנֻכָּה'));
        expect(hanukkahIndex, greaterThan(oneIndex));

        final aligned = WordAligner.align(
          script: words,
          transcript: 'אשר קידשנו במצוותיו פסטיבל להדליק נר חנוכה',
          lastConfirmedIndex: oneIndex,
          visibleSkipStartIndex: 0,
          maxSkipTargetIndex: words.length - 1,
          policy: policy,
          readingStandby: false,
        );

        expect(aligned.shouldAdvance, isTrue);
        expect(aligned.confirmedWordIndex, hanukkahIndex);
        // The misheard word must NOT be counted as evidence.
        expect(aligned.evidenceWords, isNot(contains('פסטיבל')));
        expect(policy.visibleSkip.passes(aligned.evidenceWords), isTrue);
      },
    );

    test(
      'still rejects short/noisy phrases with 1 substitution that do not reach 4.0 real evidence',
      () {
        final words = WordAligner.tokenize(blessingScript);
        final oneIndex = words.indexWhere((w) => w.raw == 'אחד');

        final aligned = WordAligner.align(
          script: words,
          transcript: 'אשר פסטיבל להדליק נר',
          lastConfirmedIndex: oneIndex,
          visibleSkipStartIndex: 0,
          maxSkipTargetIndex: words.length - 1,
          policy: policy,
          readingStandby: false,
        );

        expect(aligned.shouldAdvance, isFalse);
      },
    );

    test(
      'preservationAlignment is not hijacked by weak nextWord match העולם ~ העובדים',
      () {
        final words = WordAligner.tokenize(blessingScript);
        final oneIndex = words.indexWhere((w) => w.raw == 'אחד');
        final worldIndex = words.indexWhere((w) => w.raw.contains('הָעוֹלָם'));

        // Even with an unrelated spoken word replacing ה', אלוהינו מלך העולם
        // (3.67 < 4.0) must be preserved by preservationAlignment rather than
        // hijacked by העובדים ~ העולם and wiped via TRACK_RESET_OFF_SCRIPT.
        final preserved = const SttVisibleSkipContextService()
            .preservationAlignment(
              script: words,
              transcript: 'מילה לא קשורה אלוהינו מלך העולם',
              lastConfirmedIndex: oneIndex,
              visibleSkipStartIndex: 0,
              maxSkipTargetIndex: words.length - 1,
              policy: policy,
            );

        expect(preserved, isNotNull);
        expect(preserved!.confirmedWordIndex, worldIndex);
        expect(preserved.thresholdFamily, SttThresholdFamily.visibleSkip);
      },
    );
  });
}
