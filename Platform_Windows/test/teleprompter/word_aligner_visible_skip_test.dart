import 'package:autoteleprompter/features/script/models/script_word.dart';
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
  });
}
