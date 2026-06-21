import '../../script/models/script.dart';

class SttLocaleSectionService {
  static const String defaultLocale = 'en_US';
  static const String rtlLocale = 'he_IL';

  static List<String> sectionLocalesForScript(
    Script script, {
    int minSectionWords = 3,
  }) {
    final words = script.words.where((word) => !word.isNewline).toList();
    if (words.isEmpty) return const [];

    final raw = words
        .map((word) => word.isRtl ? rtlLocale : defaultLocale)
        .toList(growable: false);
    final smoothed = _absorbShortRuns(raw, minSectionWords: minSectionWords);

    final sectionLocales = <String>[];
    var wordIndex = 0;
    for (final word in script.words) {
      if (word.isNewline) {
        sectionLocales.add(
          sectionLocales.isNotEmpty ? sectionLocales.last : defaultLocale,
        );
      } else {
        sectionLocales.add(
          wordIndex < smoothed.length ? smoothed[wordIndex] : defaultLocale,
        );
        wordIndex++;
      }
    }
    return sectionLocales;
  }

  static int effectiveSkipThreshold({
    required List<String> sectionLocales,
    required int currentIndex,
    required String? activeLocale,
    required int normalThreshold,
    int boundaryThreshold = 5,
    int lookaheadWords = 2,
  }) {
    if (sectionLocales.isEmpty) return normalThreshold;
    for (var lookahead = 1; lookahead <= lookaheadWords; lookahead++) {
      final checkIndex = currentIndex + lookahead;
      if (checkIndex >= 0 &&
          checkIndex < sectionLocales.length &&
          sectionLocales[checkIndex] != activeLocale) {
        return boundaryThreshold;
      }
    }
    return normalThreshold;
  }

  static String localeForIndex(
    List<String> sectionLocales,
    int index, {
    String fallback = defaultLocale,
  }) {
    if (sectionLocales.isEmpty) return fallback;
    final safeIndex = index.clamp(0, sectionLocales.length - 1).toInt();
    return sectionLocales[safeIndex];
  }

  static List<String> _absorbShortRuns(
    List<String> rawLocales, {
    required int minSectionWords,
  }) {
    final smoothed = List<String>.from(rawLocales);
    var changed = true;
    while (changed) {
      changed = false;
      var index = 0;
      while (index < smoothed.length) {
        final locale = smoothed[index];
        final runStart = index;
        while (index < smoothed.length && smoothed[index] == locale) {
          index++;
        }
        final runLength = index - runStart;
        if (runLength < minSectionWords) {
          final inherit = runStart > 0
              ? smoothed[runStart - 1]
              : (index < smoothed.length ? smoothed[index] : locale);
          if (inherit != locale) {
            for (var cursor = runStart; cursor < index; cursor++) {
              smoothed[cursor] = inherit;
            }
            changed = true;
          }
        }
      }
    }
    return smoothed;
  }
}
