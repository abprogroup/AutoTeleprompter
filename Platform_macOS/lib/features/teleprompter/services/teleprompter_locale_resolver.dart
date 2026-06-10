import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';

class TeleprompterLocaleResolver {
  const TeleprompterLocaleResolver._();

  static bool visibleTranscriptPlausiblyMatchesLocale({
    required List<ScriptWord> words,
    required List<String> sectionLocales,
    required String locale,
    required String transcript,
    required int visibleStart,
    required int visibleEnd,
    required int currentIndex,
  }) {
    if (words.isEmpty || sectionLocales.length != words.length) return false;
    final start = visibleStart.clamp(0, words.length - 1).toInt();
    final end = visibleEnd.clamp(start, words.length - 1).toInt();
    final minIndex = (currentIndex + 1).clamp(0, end).toInt();
    final scanStart = start < minIndex ? minIndex : start;
    if (scanStart > end) return false;

    final visible = <String>[];
    for (var i = scanStart; i <= end; i++) {
      final word = words[i];
      if (!wordCarriesLanguage(word)) continue;
      if (sectionLocales[i] != locale) continue;
      visible.add(word.normalized.normalizeForMatching());
    }
    if (visible.isEmpty) return false;

    final spoken = transcript
        .split(RegExp(r'\s+'))
        .map((w) => w.trim().normalizeForMatching())
        .where((w) => w.isNotEmpty)
        .toList();
    if (spoken.isEmpty) return false;

    var usefulMatches = 0;
    for (final spokenWord in spoken) {
      if (_visibleAssistStopWords.contains(spokenWord)) continue;
      var best = 0.0;
      for (final visibleWord in visible) {
        final sim = spokenWord.similarity(visibleWord);
        if (sim > best) best = sim;
      }
      if (best >= 0.92 && spokenWord.length >= 4) {
        usefulMatches++;
      }
      if (best >= 0.96 && spokenWord.length >= 6) {
        return true;
      }
    }
    return usefulMatches >= 2;
  }

  static bool shouldBlockLocaleSyncDuringAssistPin({
    required String? pinnedLocale,
    required String? activeLocale,
    required String? scriptLocale,
    required DateTime? pinnedUntil,
    required DateTime now,
  }) {
    if (pinnedLocale == null || pinnedUntil == null) return false;
    if (!now.isBefore(pinnedUntil)) return false;
    return pinnedLocale == activeLocale || pinnedLocale == scriptLocale;
  }

  static String? explicitLocaleForWord(ScriptWord word) {
    if (word.isNewline) return null;
    if (word.normalized.isEmpty) return null;
    final text = word.normalized;
    if (RegExp(r'[\u0590-\u05FF]').hasMatch(text)) return 'he_IL';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en_US';
    return null;
  }

  static bool wordCarriesLanguage(ScriptWord word) =>
      explicitLocaleForWord(word) != null;

  static List<String> resolveSectionLocalesForWords(List<ScriptWord> words) {
    const minSectionWords = 2;

    final languageEntries = <({int index, String locale})>[];
    for (var i = 0; i < words.length; i++) {
      final locale = explicitLocaleForWord(words[i]);
      if (locale != null) languageEntries.add((index: i, locale: locale));
    }

    if (words.isEmpty) return [];
    if (languageEntries.isEmpty) {
      return List<String>.filled(words.length, 'en_US');
    }

    final smoothed = [for (final entry in languageEntries) entry.locale];
    var changed = true;
    while (changed) {
      changed = false;
      var i = 0;
      while (i < smoothed.length) {
        final locale = smoothed[i];
        final runStart = i;
        while (i < smoothed.length && smoothed[i] == locale) {
          i++;
        }
        final runLen = i - runStart;
        if (runLen < minSectionWords) {
          final inherit = runStart > 0
              ? smoothed[runStart - 1]
              : (i < smoothed.length ? smoothed[i] : locale);
          if (inherit != locale) {
            for (var j = runStart; j < i; j++) {
              smoothed[j] = inherit;
            }
            changed = true;
          }
        }
      }
    }

    final explicitLocales = <int, String>{
      for (var i = 0; i < languageEntries.length; i++)
        languageEntries[i].index: smoothed[i],
    };

    return [
      for (var i = 0; i < words.length; i++)
        explicitLocales[i] ??
            _inheritLocaleForNeutralWord(
              words,
              explicitLocales,
              i,
            ),
    ];
  }

  static String resolveInitialSttLocale(
    List<ScriptWord> words, {
    int startIndex = 0,
    List<String>? sectionLocales,
  }) {
    if (words.isEmpty) return 'en_US';

    final safeStart = startIndex.clamp(0, words.length - 1).toInt();
    var hebrew = 0;
    var english = 0;
    String? firstLocale;

    for (var i = safeStart; i < words.length && hebrew + english < 5; i++) {
      final locale = explicitLocaleForWord(words[i]);
      if (locale == null) continue;
      firstLocale ??= locale;
      if (locale == 'he_IL') {
        hebrew++;
      } else {
        english++;
      }
    }

    if (hebrew > english) return 'he_IL';
    if (english > hebrew) return 'en_US';
    if (firstLocale != null) return firstLocale;

    if (sectionLocales != null && sectionLocales.isNotEmpty) {
      return sectionLocales[safeStart.clamp(0, sectionLocales.length - 1)];
    }
    return 'en_US';
  }

  static const Set<String> _visibleAssistStopWords = {
    'a',
    'an',
    'and',
    'at',
    'for',
    'in',
    'is',
    'of',
    'or',
    'the',
    'to',
    'we',
    'you',
  };

  static String _inheritLocaleForNeutralWord(
    List<ScriptWord> words,
    Map<int, String> explicitLocales,
    int index,
  ) {
    String? scan(int step, {required bool stopAtNewline}) {
      var i = index + step;
      while (i >= 0 && i < words.length) {
        if (stopAtNewline && words[i].isNewline) return null;
        final locale = explicitLocales[i];
        if (locale != null) return locale;
        i += step;
      }
      return null;
    }

    final previousInParagraph = scan(-1, stopAtNewline: true);
    final nextInParagraph = scan(1, stopAtNewline: true);
    if (previousInParagraph != null) return previousInParagraph;
    if (nextInParagraph != null) return nextInParagraph;

    return scan(-1, stopAtNewline: false) ??
        scan(1, stopAtNewline: false) ??
        'en_US';
  }
}
