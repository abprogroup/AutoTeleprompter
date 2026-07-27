part of 'word_aligner.dart';

bool _hasUsefulPhraseWords(List<String> phrase, int minPhraseWords) {
  var useful = 0;
  for (final word in phrase) {
    if (!_phraseStopWords.contains(word)) useful++;
  }
  return useful >= (minPhraseWords == 2 ? 1 : 2);
}

const Set<String> _phraseStopWords = {
  'a',
  'an',
  'and',
  'as',
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

/// Compute similarity between a spoken word and a script word, with special
/// handling for Hebrew prefix stripping.
double _wordSimilarity(String spoken, String scriptWord, bool isRtl) {
  if (spoken == scriptWord) return 1.0;
  if (spoken.isEmpty || scriptWord.isEmpty) return 0.0;

  double sim = spoken.similarity(scriptWord);

  if (sim < 0.80 && spoken.length >= 3 && scriptWord.length >= 3) {
    if (spoken.contains(scriptWord) || scriptWord.contains(spoken)) {
      final shorter =
          spoken.length < scriptWord.length ? spoken.length : scriptWord.length;
      final longer =
          spoken.length > scriptWord.length ? spoken.length : scriptWord.length;
      final subSim = 0.70 * (shorter / longer) + 0.25;
      if (subSim > sim) sim = subSim;
    }
  }

  if (isRtl && sim < 0.75) {
    final ss = scriptWord.stripHebrewPrefixes();
    final ls = spoken.stripHebrewPrefixes();
    if (ss == ls || ss == spoken || scriptWord == ls) {
      sim = 0.88;
    } else {
      final prefixSim = ls.similarity(ss);
      if (prefixSim > sim) sim = prefixSim * 0.92;
    }

    if (sim < 0.65) {
      final phoneticSpoken = _hebrewPhonetic(spoken);
      final phoneticScript = _hebrewPhonetic(scriptWord);
      final phoneticSim = phoneticSpoken.similarity(phoneticScript);
      if (phoneticSim > sim) sim = phoneticSim * 0.90;

      final phoneticSS = _hebrewPhonetic(ss);
      final phoneticLS = _hebrewPhonetic(ls);
      final phoneticPrefixSim = phoneticLS.similarity(phoneticSS);
      if (phoneticPrefixSim > sim) sim = phoneticPrefixSim * 0.88;
    }

    if (sim < 0.60 && ls.length >= 3 && ss.length >= 3) {
      if (ls.contains(ss) || ss.contains(ls)) {
        final overlapRatio = (ls.length < ss.length ? ls.length : ss.length) /
            (ls.length > ss.length ? ls.length : ss.length);
        final subSim = 0.70 * overlapRatio + 0.20;
        if (subSim > sim) sim = subSim;
      }
    }
  }

  return sim;
}

/// Normalize Hebrew letters that sound the same for phonetic comparison.
String _hebrewPhonetic(String s) {
  return s
      .replaceAll('\u05E7', '\u05DB') // qof -> kaf
      .replaceAll('\u05D8', '\u05EA') // tet -> tav
      .replaceAll('\u05E1', '\u05E9') // samekh -> shin
      .replaceAll('\u05E2', '\u05D0') // ayin -> alef
      .replaceAll('\u05D5', '\u05D1'); // vav -> bet
}

/// Collapse sequences of single-character words into abbreviation candidates.
List<String> _collapseAbbreviations(List<String> words) {
  if (words.length < 2) return words;
  final result = <String>[];
  int i = 0;
  while (i < words.length) {
    if (words[i].length == 1 && !words[i].isHebrew) {
      int j = i;
      while (j < words.length &&
          words[j].length == 1 &&
          !words[j].isHebrew &&
          j - i < 6) {
        j++;
      }
      if (j - i >= 2) {
        result.add(words.sublist(i, j).join(''));
      }
      result.addAll(words.sublist(i, j));
      i = j;
    } else {
      result.add(words[i]);
      i++;
    }
  }
  return result;
}

bool _isUnspeakable(ScriptWord word) {
  if (word.isNewline) return true;
  final norm = word.normalized;
  if (norm.isEmpty) return true;
  // Numbers, dots, colons, dashes (e.g. 7.10.24, 20:30, 96, 12-34).
  if (RegExp(r'^[0-9\.:\-\/]+$').hasMatch(norm)) return true;
  return false;
}
