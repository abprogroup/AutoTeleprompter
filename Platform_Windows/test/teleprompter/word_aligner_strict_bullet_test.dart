import 'package:autoteleprompter/features/script/models/script_word.dart';
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
  group('Windows strict bullet/header STT', () {
    test('normal mode waits for at least three spoken words', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma', 'delta']);

      final result = WordAligner.align(
        script: script,
        transcript: 'delta',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 0);
      expect(result.debugInfo, contains('WAIT_MIN_WORDS'));
    });

    test('normal mode advances after three spoken words confirm position', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma', 'delta']);

      final result = WordAligner.align(
        script: script,
        transcript: 'beta gamma delta',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 4);
    });

    test('strict mode blocks local single-word guessed skips', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma', 'delta']);

      final result = WordAligner.align(
        script: script,
        transcript: 'delta',
        lastConfirmedIndex: 0,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 0);
    });

    test('strict mode still advances on deliberate next word', () {
      final script = _words(['intro', 'alpha', 'beta']);

      final result = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 1);
      expect(result.confidence, greaterThanOrEqualTo(0.82));
    });

    test('strict mode allows visible multi-word bullet jump', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma', 'delta']);

      final result = WordAligner.align(
        script: script,
        transcript: 'gamma delta',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: 4,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 4);
      expect(result.confidence, greaterThanOrEqualTo(0.78));
    });

    test('strict mode relocks to a visible phrase after improvised preface',
        () {
      final script = _words([
        'intro',
        'alpha',
        'beta',
        'story',
        'of',
        'the',
        'Samaritan',
        'woman',
        'at',
        'the',
        'well',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript:
            'today I want to explain this with my own words story of the Samaritan woman and then continue',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 7);
      expect(result.confidence, greaterThanOrEqualTo(0.78));
    });

    test('strict mode allows visible Hebrew phrase jump', () {
      final script = [
        _word('intro', 0),
        _word(_hOpening, 1, rtl: true),
        _word(_hBlessing, 2, rtl: true),
        _word(_hClosing, 3, rtl: true),
      ];

      final result = WordAligner.align(
        script: script,
        transcript: '$_hBlessing $_hClosing',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: 3,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 3);
      expect(result.confidence, greaterThanOrEqualTo(0.78));
    });

    test('strict mode relocks to visible Hebrew after improvised preface', () {
      final script = [
        _word('intro', 0),
        _word(_hOpening, 1, rtl: true),
        _word(_hBlessing, 2, rtl: true),
        _word(_hClosing, 3, rtl: true),
      ];

      final result = WordAligner.align(
        script: script,
        transcript: 'random words before $_hOpening $_hBlessing after',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: 3,
        strictBulletMode: true,
      );

      expect(result.confirmedWordIndex, 2);
      expect(result.confidence, greaterThanOrEqualTo(0.78));
    });

    test('strict mode disables provider force-skip', () {
      expect(
        TeleprompterNotifier.shouldForceSkipAfterNoProgress(
          strictBulletMode: true,
          noProgressCount: 100,
          skipThreshold: 45,
        ),
        isFalse,
      );

      expect(
        TeleprompterNotifier.shouldForceSkipAfterNoProgress(
          strictBulletMode: false,
          noProgressCount: 45,
          skipThreshold: 45,
        ),
        isTrue,
      );
    });

    test('strict mode uses visible window even when visible skip toggle is off',
        () {
      expect(
        TeleprompterNotifier.resolveVisibleSkipTarget(
          visibleSkipEnabled: false,
          strictBulletMode: true,
          visibleWordStart: 10,
          visibleWordEnd: 40,
        ),
        40,
      );

      expect(
        TeleprompterNotifier.resolveVisibleSkipTarget(
          visibleSkipEnabled: false,
          strictBulletMode: false,
          visibleWordStart: 10,
          visibleWordEnd: 40,
        ),
        isNull,
      );
    });

    test('strict improvisation suppresses normal stuck recovery', () {
      expect(
        TeleprompterNotifier.shouldUseImprovisationNoMatch(
          strictBulletMode: true,
          alignedIndex: 0,
          currentIndex: 0,
        ),
        isTrue,
      );

      expect(
        TeleprompterNotifier.shouldUseImprovisationNoMatch(
          strictBulletMode: false,
          alignedIndex: 0,
          currentIndex: 0,
        ),
        isFalse,
      );
    });

    test('strict improvisation caps standby wait counter', () {
      expect(
        TeleprompterNotifier.nextNoProgressCount(
          currentCount: 20,
          improvising: true,
          visibleAssistThreshold: 2,
        ),
        2,
      );

      expect(
        TeleprompterNotifier.nextNoProgressCount(
          currentCount: 20,
          improvising: false,
          visibleAssistThreshold: 2,
        ),
        21,
      );
    });

    test('visible relock ignores stale words before the visible start', () {
      final script = _words([
        'intro',
        'one',
        'two',
        'three',
        'four',
        'five',
        'hidden',
        'target',
        'phrase',
        'visible',
        'safe',
        'heading',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'hidden target phrase',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 9,
        maxSkipTargetIndex: 11,
        strictBulletMode: false,
      );

      expect(result.confirmedWordIndex, 0);
    });

    test('provider trusts only targets inside the visible window', () {
      expect(
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
          alignedIndex: 12,
          visibleWordStart: 10,
          visibleWordEnd: 20,
        ),
        isTrue,
      );

      expect(
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
          alignedIndex: 8,
          visibleWordStart: 10,
          visibleWordEnd: 20,
        ),
        isFalse,
      );
    });
  });
}
