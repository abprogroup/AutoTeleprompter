import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _hToday = '\u05d4\u05d9\u05d5\u05dd';
const _hHope = '\u05ea\u05e7\u05d5\u05d5\u05d4';
const _hChildren = '\u05d9\u05dc\u05d3\u05d9\u05dd';
const _hLearn = '\u05dc\u05d5\u05de\u05d3\u05d9\u05dd';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

ScriptWord _newline(int index) => ScriptWord(
      raw: '\n',
      normalized: '',
      index: index,
      isRtl: false,
      isNewline: true,
    );

void main() {
  group('Windows STT locale resolution', () {
    test(
        'starts Hebrew when the first language words after a number are Hebrew',
        () {
      final words = [
        _word('15.10', 0),
        _word(_hToday, 1, rtl: true),
        _word(_hHope, 2, rtl: true),
        _word(_hChildren, 3, rtl: true),
        _word(_hLearn, 4, rtl: true),
      ];

      final locales = TeleprompterNotifier.resolveSectionLocalesForWords(words);

      expect(locales.first, 'he_IL');
      expect(
        TeleprompterNotifier.resolveInitialSttLocale(
          words,
          sectionLocales: locales,
        ),
        'he_IL',
      );
    });

    test(
        'starts English when the first language words after a number are English',
        () {
      final words = [
        _word('15.10', 0),
        _word('opening', 1),
        _word('words', 2),
        _word('begin', 3),
        _word('here', 4),
      ];

      final locales = TeleprompterNotifier.resolveSectionLocalesForWords(words);

      expect(locales.first, 'en_US');
      expect(
        TeleprompterNotifier.resolveInitialSttLocale(
          words,
          sectionLocales: locales,
        ),
        'en_US',
      );
    });

    test('signs and numbers inherit language without creating locale sections',
        () {
      final words = [
        _word('[', 0),
        _word('15', 1),
        _word(_hChildren, 2, rtl: true),
        _word('-', 3),
        _word(_hLearn, 4, rtl: true),
        _newline(5),
        _word('50', 6),
        _word('english', 7),
        _word('section', 8),
      ];

      final locales = TeleprompterNotifier.resolveSectionLocalesForWords(words);

      expect(locales.sublist(0, 5), everyElement('he_IL'));
      expect(locales.sublist(6, 9), everyElement('en_US'));
    });

    test('initial locale checks the first five language-bearing words only',
        () {
      final words = [
        _word('...', 0),
        _word('50', 1),
        _word(_hToday, 2, rtl: true),
        _word(_hHope, 3, rtl: true),
        _word(_hChildren, 4, rtl: true),
        _word('later', 5),
        _word('english', 6),
        _word('words', 7),
      ];

      expect(TeleprompterNotifier.resolveInitialSttLocale(words), 'he_IL');
    });
  });
}
