import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_visible_relock_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

const _hShalom = '\u05e9\u05dc\u05d5\u05dd';
const _hOpening = '\u05e4\u05ea\u05d9\u05d7\u05d4';
const _hFirst = '\u05e8\u05d0\u05e9\u05d5\u05e0\u05d4';
const _hHebrew = '\u05e2\u05d1\u05e8\u05d9\u05ea';
const _hMiddle = '\u05d0\u05de\u05e6\u05e2';
const _hReturn = '\u05d7\u05d6\u05e8\u05d4';
const _hSection = '\u05dc\u05de\u05e7\u05d8\u05e2';
const _hNext = '\u05d4\u05d1\u05d0';
const _hSafe = '\u05d1\u05d8\u05d5\u05d7';
const _hCome = '\u05d1\u05d5\u05d0\u05d5';
const _hAdvance = '\u05e0\u05ea\u05e7\u05d3\u05dd';
const _hCeremony = '\u05d1\u05d8\u05e7\u05e1';
const _hStage = '\u05e9\u05dc\u05d1';
const _hRings = '\u05d4\u05d8\u05d1\u05e2\u05d5\u05ea';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

List<ScriptWord> _mixedScript({
  required bool startWithHebrew,
  required bool endWithHebrew,
  int middleCount = 64,
}) {
  final words = <ScriptWord>[];

  void add(String raw, {bool rtl = false}) {
    words.add(_word(raw, words.length, rtl: rtl));
  }

  if (startWithHebrew) {
    add(_hShalom, rtl: true);
    add(_hOpening, rtl: true);
    add(_hFirst, rtl: true);
  } else {
    add('opening');
    add('english');
    add('start');
  }

  for (var i = 0; i < middleCount; i++) {
    if (startWithHebrew) {
      add('english');
      add('middle');
    } else {
      add(_hHebrew, rtl: true);
      add(_hMiddle, rtl: true);
    }
  }

  if (endWithHebrew) {
    add(_hReturn, rtl: true);
    add(_hSection, rtl: true);
    add(_hNext, rtl: true);
    add(_hSafe, rtl: true);
  } else {
    add('returning');
    add('english');
    add('section');
    add('finale');
  }

  return words;
}

List<ScriptWord> _storyWindowScript() {
  final raw = [
    'overlooked',
    'by',
    'man',
    'but',
    'precious',
    'to',
    'God',
    'Yeshua',
    'met',
    'them',
    'Join',
    'us',
    'next',
    'time',
    'as',
    'we',
    'visit',
    'the',
    'story',
    'of',
    'the',
    'Samaritan',
    'woman',
    'at',
    'the',
    'well',
    _hReturn,
    _hSection,
    _hNext,
  ];
  return [
    for (var i = 0; i < raw.length; i++)
      _word(raw[i], i, rtl: i >= raw.length - 3),
  ];
}

List<String> _localesFor(List<ScriptWord> words) {
  return [for (final word in words) word.isRtl ? 'he_IL' : 'en_US'];
}

void main() {
  group('Windows visible STT skip', () {
    test('finds English phrase after visible Hebrew section', () {
      final script = _mixedScript(startWithHebrew: false, endWithHebrew: false);
      final result = WordAligner.align(
        script: script,
        transcript: 'returning english section finale',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
      expect(result.confidence, greaterThanOrEqualTo(0.55));
    });

    test('finds Hebrew phrase after visible English section', () {
      final script = _mixedScript(startWithHebrew: true, endWithHebrew: true);
      final result = WordAligner.align(
        script: script,
        transcript: '$_hReturn $_hSection $_hNext $_hSafe',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
      expect(result.confidence, greaterThanOrEqualTo(0.55));
    });

    test('finds Hebrew phrase when visible skip crosses from English', () {
      final script = _mixedScript(startWithHebrew: false, endWithHebrew: true);
      final result = WordAligner.align(
        script: script,
        transcript: '$_hReturn $_hSection $_hNext $_hSafe',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
    });

    test('finds English phrase when visible skip crosses from Hebrew', () {
      final script = _mixedScript(startWithHebrew: true, endWithHebrew: false);
      final result = WordAligner.align(
        script: script,
        transcript: 'returning english section finale',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
    });

    test('keeps large phrase jump blocked when visible skip is off', () {
      final script = _mixedScript(startWithHebrew: false, endWithHebrew: false);
      final result = WordAligner.align(
        script: script,
        transcript: 'returning english section finale',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 0);
    });

    test('hard visible skip raises the visible phrase threshold', () {
      final script = _mixedScript(startWithHebrew: false, endWithHebrew: false);
      final hardPolicy = SttRecognitionPolicy.legacy(
        visibleSkipEnabled: true,
        hardVisibleSkipEnabled: true,
      );

      final tooShort = WordAligner.align(
        script: script,
        transcript: 'returning english section',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
        policy: hardPolicy,
      );
      final enough = WordAligner.align(
        script: script,
        transcript: 'returning english section finale',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
        policy: hardPolicy,
      );

      expect(tooShort.confirmedWordIndex, 0);
      expect(enough.confirmedWordIndex, script.length - 1);
    });

    test('visible Hebrew phrase can bridge one missed script word', () {
      final words = <ScriptWord>[];

      void add(String raw, {bool rtl = false}) {
        words.add(_word(raw, words.length, rtl: rtl));
      }

      add('intro');
      add('setup');
      add(_hCome, rtl: true);
      add(_hAdvance, rtl: true);
      add(_hCeremony, rtl: true);
      add(_hStage, rtl: true);
      add(_hRings, rtl: true);

      final result = WordAligner.align(
        script: words,
        transcript: '$_hCome $_hAdvance $_hStage $_hRings',
        lastConfirmedIndex: 0,
        visibleSkipStartIndex: 0,
        maxSkipTargetIndex: words.length - 1,
        policy: SttRecognitionPolicy.legacy(visibleSkipEnabled: true),
      );

      expect(result.confirmedWordIndex, words.length - 1);
      expect(result.debugInfo, contains('gapCost=1.0'));
    });

    test('provider does not cap trusted visible-skip alignments', () {
      final target = TeleprompterNotifier.resolveAdvanceTarget(
        currentIndex: 21,
        alignedIndex: 85,
        visibleMaxSkipTargetIndex: 85,
      );

      expect(target, 85);
    });

    test('provider still caps non-visible large advances', () {
      final target = TeleprompterNotifier.resolveAdvanceTarget(
        currentIndex: 21,
        alignedIndex: 85,
        visibleMaxSkipTargetIndex: null,
      );

      expect(target, 51);
    });

    test('provider fuzzy relock is clamped to visible window end', () {
      final words = [
        _word('visible', 0),
        _word('camera', 1),
        _word('settings', 2),
        _word('recording', 3),
        _word('hidden', 4),
        _word('both', 5),
        _word('of', 6),
        _word('them', 7),
        _word('are', 8),
        _word('good', 9),
      ];

      final target = const SttVisibleRelockService().fuzzyTarget(
        words: words,
        transcript: 'both of them are good',
        visibleWordStart: 0,
        visibleWordEnd: 3,
      );

      expect(target, isNull);
    });

    test('provider fuzzy relock accepts phrase inside visible window', () {
      final words = [
        _word('title', 0),
        _word('both', 1),
        _word('of', 2),
        _word('them', 3),
        _word('are', 4),
        _word('good', 5),
        _word('footer', 6),
      ];

      final target = const SttVisibleRelockService().fuzzyTarget(
        words: words,
        transcript: 'both of them are good',
        visibleWordStart: 1,
        visibleWordEnd: 5,
      );

      expect(target, 5);
    });

    test('provider approximate relock finds phrase inside visible window', () {
      final words = [
        _word('title', 0),
        _word('intro', 1),
        _word('both', 2),
        _word('of', 3),
        _word('them', 4),
        _word('are', 5),
        _word('good', 6),
        _word('business', 7),
        _word('people', 8),
        _word('right', 9),
        _word('footer', 10),
      ];

      final target = const SttVisibleRelockService().approximateTarget(
        words: words,
        transcript: 'the setup was long but both of them are good business '
            'people right and then the speaker kept going',
        currentIndex: 0,
        visibleWordStart: 1,
        visibleWordEnd: 10,
      );

      expect(target, 9);
    });

    test('provider approximate relock does not search outside visible window',
        () {
      final words = [
        _word('visible', 0),
        _word('camera', 1),
        _word('settings', 2),
        _word('recording', 3),
        _word('hidden', 4),
        _word('both', 5),
        _word('of', 6),
        _word('them', 7),
        _word('are', 8),
        _word('good', 9),
        _word('business', 10),
        _word('people', 11),
        _word('right', 12),
      ];

      final target = const SttVisibleRelockService().approximateTarget(
        words: words,
        transcript: 'both of them are good business people right',
        currentIndex: 0,
        visibleWordStart: 0,
        visibleWordEnd: 3,
      );

      expect(target, isNull);
    });

    test('provider approximate relock can relax inside visible window', () {
      final words = [
        _word('visible', 0),
        _word('camera', 1),
        _word('both', 2),
        _word('of', 3),
        _word('them', 4),
        _word('are', 5),
        _word('good', 6),
        _word('business', 7),
        _word('people', 8),
        _word('right', 9),
      ];

      final strict = const SttVisibleRelockService().approximateTarget(
        words: words,
        transcript: 'both of them were good business people right',
        currentIndex: 0,
        visibleWordStart: 1,
        visibleWordEnd: 9,
      );
      final relaxed = const SttVisibleRelockService().approximateTarget(
        words: words,
        transcript: 'both of them were good business people right',
        currentIndex: 0,
        visibleWordStart: 1,
        visibleWordEnd: 9,
        minimumScore: 0.76,
      );

      expect(strict, isNull);
      expect(relaxed, 9);
    });

    test('provider rolling transcript windows recover earlier visible phrase',
        () {
      final words = [
        _word('1', 0),
        _word('Video', 1),
        _word('Scripts', 2),
        _word('both', 3),
        _word('of', 4),
        _word('them', 5),
        _word('are', 6),
        _word('good', 7),
        _word('business', 8),
        _word('people', 9),
        _word('right', 10),
      ];
      const transcript =
          'both of them are good business people right and then the speaker '
          'kept improvising with many extra words that moved the useful '
          'phrase away from the latest recognition suffix';
      final windows = TeleprompterNotifier.rollingTranscriptWindowsForAlignment(
        transcript,
        windowWords: 8,
        maxWindows: 5,
      );

      expect(windows.first, isNot(contains('both of them')));
      expect(
        windows.any((window) => window.contains('both of them are good')),
        isTrue,
      );

      final targets = [
        for (final window in windows)
          WordAligner.align(
            script: words,
            transcript: window,
            lastConfirmedIndex: 0,
            visibleSkipStartIndex: 0,
            maxSkipTargetIndex: words.length - 1,
            policy: SttRecognitionPolicy.legacy(visibleSkipEnabled: true),
          ).confirmedWordIndex,
      ];

      expect(targets.any((target) => target >= 7), isTrue);
    });

    test('plausible active English text blocks visible Hebrew assist', () {
      final script = _storyWindowScript();
      final plausible =
          TeleprompterNotifier.visibleTranscriptPlausiblyMatchesLocale(
        words: script,
        sectionLocales: _localesFor(script),
        locale: 'en_US',
        transcript: 'story of the Samaritan woman at the well',
        visibleStart: 0,
        visibleEnd: script.length - 1,
        currentIndex: 6,
      );

      expect(plausible, isTrue);
    });

    test('wrong-language gibberish does not block visible Hebrew assist', () {
      final script = _storyWindowScript();
      final plausible =
          TeleprompterNotifier.visibleTranscriptPlausiblyMatchesLocale(
        words: script,
        sectionLocales: _localesFor(script),
        locale: 'en_US',
        transcript: 'that text livdo kaim niktanik vods ben stafford',
        visibleStart: 0,
        visibleEnd: script.length - 1,
        currentIndex: 6,
      );

      expect(plausible, isFalse);
    });

    test('assist pin blocks heartbeat locale sync until expiry', () {
      final now = DateTime(2026, 5, 4, 12);

      expect(
        TeleprompterNotifier.shouldBlockLocaleSyncDuringAssistPin(
          pinnedLocale: 'he_IL',
          activeLocale: 'he_IL',
          scriptLocale: 'he_IL',
          pinnedUntil: now.add(const Duration(seconds: 3)),
          now: now,
        ),
        isTrue,
      );

      expect(
        TeleprompterNotifier.shouldBlockLocaleSyncDuringAssistPin(
          pinnedLocale: 'he_IL',
          activeLocale: 'he_IL',
          scriptLocale: 'he_IL',
          pinnedUntil: now.subtract(const Duration(milliseconds: 1)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
