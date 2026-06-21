import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_locale_section_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SttLocaleSectionService', () {
    test('absorbs short language runs into surrounding sections', () {
      final script = _script([
        _word('Today', 0),
        _word('we', 1),
        _word('speak', 2),
        _word('שלום', 3, rtl: true),
        _word('world', 4),
        _word('again', 5),
        _word('now', 6),
      ]);

      final locales = SttLocaleSectionService.sectionLocalesForScript(script);

      expect(locales, everyElement(SttLocaleSectionService.defaultLocale));
    });

    test('keeps real sections and lets newlines inherit previous locale', () {
      final script = _script([
        _word('Today', 0),
        _word('we', 1),
        _word('read', 2),
        _newline(3),
        _word('שלום', 4, rtl: true),
        _word('עולם', 5, rtl: true),
        _word('עכשיו', 6, rtl: true),
      ]);

      final locales = SttLocaleSectionService.sectionLocalesForScript(script);

      expect(locales[0], SttLocaleSectionService.defaultLocale);
      expect(locales[1], SttLocaleSectionService.defaultLocale);
      expect(locales[2], SttLocaleSectionService.defaultLocale);
      expect(locales[3], SttLocaleSectionService.defaultLocale);
      expect(locales[4], SttLocaleSectionService.rtlLocale);
      expect(locales[5], SttLocaleSectionService.rtlLocale);
      expect(locales[6], SttLocaleSectionService.rtlLocale);
    });

    test('tightens skip threshold near a section boundary only', () {
      const locales = [
        'en_US',
        'en_US',
        'en_US',
        'he_IL',
        'he_IL',
      ];

      expect(
        SttLocaleSectionService.effectiveSkipThreshold(
          sectionLocales: locales,
          currentIndex: 0,
          activeLocale: 'en_US',
          normalThreshold: 45,
        ),
        45,
      );
      expect(
        SttLocaleSectionService.effectiveSkipThreshold(
          sectionLocales: locales,
          currentIndex: 1,
          activeLocale: 'en_US',
          normalThreshold: 45,
        ),
        5,
      );
    });

    test('localeForIndex clamps safely', () {
      const locales = ['en_US', 'he_IL'];

      expect(
        SttLocaleSectionService.localeForIndex(locales, -20),
        'en_US',
      );
      expect(
        SttLocaleSectionService.localeForIndex(locales, 200),
        'he_IL',
      );
      expect(
        SttLocaleSectionService.localeForIndex(const [], 0),
        SttLocaleSectionService.defaultLocale,
      );
    });
  });
}

Script _script(List<ScriptWord> words) {
  return Script(
    id: 'script',
    title: 'Script',
    rawText: words.map((word) => word.raw).join(' '),
    words: words,
    isRtl: false,
    sessionId: 'session',
  );
}

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

ScriptWord _newline(int index) {
  return ScriptWord(
    raw: '\n',
    normalized: '',
    index: index,
    isRtl: false,
    isNewline: true,
  );
}
