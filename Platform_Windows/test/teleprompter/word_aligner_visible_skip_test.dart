import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
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
  } else {
    add('returning');
    add('english');
    add('section');
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
        transcript: 'returning english section',
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
        transcript: '$_hReturn $_hSection $_hNext',
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
        transcript: '$_hReturn $_hSection $_hNext',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
    });

    test('finds English phrase when visible skip crosses from Hebrew', () {
      final script = _mixedScript(startWithHebrew: true, endWithHebrew: false);
      final result = WordAligner.align(
        script: script,
        transcript: 'returning english section',
        lastConfirmedIndex: 0,
        maxSkipTargetIndex: script.length - 1,
      );

      expect(result.confirmedWordIndex, script.length - 1);
    });

    test('keeps large phrase jump blocked when visible skip is off', () {
      final script = _mixedScript(startWithHebrew: false, endWithHebrew: false);
      final result = WordAligner.align(
        script: script,
        transcript: 'returning english section',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 0);
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
