import 'dart:io';

class SherpaTokenVocab {
  final Set<String> tokens;
  final int maxTokenLength;
  final bool uppercaseLatin;
  final bool usesSentencePieceSpace;

  const SherpaTokenVocab({
    required this.tokens,
    required this.maxTokenLength,
    required this.uppercaseLatin,
    required this.usesSentencePieceSpace,
  });

  static SherpaTokenVocab? fromFile(String tokensPath) {
    final file = File(tokensPath);
    if (!file.existsSync()) return null;
    return fromContent(file.readAsStringSync());
  }

  static SherpaTokenVocab fromContent(String content) {
    final tokens = <String>{};
    var maxLen = 1;
    var upperCount = 0;
    var lowerCount = 0;
    var spCount = 0;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;
      final splitIdx = line.lastIndexOf(' ');
      final token = splitIdx > 0 ? line.substring(0, splitIdx) : line;
      if (token.isEmpty) continue;
      if (token.startsWith('<') && token.endsWith('>')) continue;

      tokens.add(token);
      if (token.length > maxLen) maxLen = token.length;
      if (token.startsWith('\u2581')) spCount++;

      for (var i = 0; i < token.length; i++) {
        final code = token.codeUnitAt(i);
        if (code >= 65 && code <= 90) {
          upperCount++;
        } else if (code >= 97 && code <= 122) {
          lowerCount++;
        }
      }
    }

    return SherpaTokenVocab(
      tokens: tokens,
      maxTokenLength: maxLen,
      uppercaseLatin: upperCount > lowerCount,
      usesSentencePieceSpace: spCount > 0,
    );
  }

  /// Tokenizes a single cleaned word into space-separated vocabulary tokens
  /// accepted by `sherpa-onnx` hotwords, or returns `null` if it cannot be
  /// represented cleanly in this model's `tokens.txt`.
  String? tokenizeWord(String rawWord) {
    final cleaned = _cleanWord(rawWord);
    if (cleaned.length < 3) return null;

    final cased =
        _hasLatin(cleaned)
            ? (uppercaseLatin ? cleaned.toUpperCase() : cleaned.toLowerCase())
            : cleaned;
    final target = usesSentencePieceSpace ? '\u2581$cased' : cased;

    final pieces = <String>[];
    var pos = 0;
    while (pos < target.length) {
      String? matched;
      final limit =
          pos + maxTokenLength < target.length
              ? pos + maxTokenLength
              : target.length;
      for (var end = limit; end > pos; end--) {
        final sub = target.substring(pos, end);
        if (tokens.contains(sub)) {
          matched = sub;
          pos = end;
          break;
        }
      }
      if (matched == null) return null;
      pieces.add(matched);
    }

    if (pieces.isEmpty) return null;
    return pieces.join(' ');
  }

  static String _cleanWord(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '')
        .replaceAll(RegExp(r"[^\p{L}']", unicode: true), '')
        .replaceAll(RegExp(r"^'+|'+$"), '')
        .trim();
  }

  static bool _hasLatin(String text) => RegExp(r'[A-Za-z]').hasMatch(text);
}

class SherpaHotwordsResult {
  final String text;
  final int wordCount;

  const SherpaHotwordsResult({required this.text, required this.wordCount});
}

class SherpaHotwordsBuilder {
  const SherpaHotwordsBuilder._();

  static const int defaultMaxWords = 64;

  static const Set<String> _commonStopWords = {
    'the',
    'and',
    'that',
    'this',
    'with',
    'from',
    'have',
    'your',
    'they',
    'what',
    'when',
    'where',
    'which',
    'their',
    'there',
    'about',
    'would',
    'could',
    'should',
    'into',
    'just',
    'like',
    'some',
    'them',
    'than',
    'then',
    'also',
    'been',
    'were',
    'will',
    'more',
    'very',
    'only',
    'here',
  };

  /// Selects up to [maxWords] meaningful unique words from [scriptWords],
  /// prioritizing words at and ahead of [startIndex] so long scripts focus on
  /// the upcoming section being read.
  static List<String> selectScriptWords(
    List<String> scriptWords, {
    int startIndex = 0,
    int maxWords = defaultMaxWords,
  }) {
    if (scriptWords.isEmpty || maxWords <= 0) return const [];
    final safeStart = startIndex.clamp(0, scriptWords.length - 1).toInt();
    final seen = <String>{};
    final selected = <String>[];

    void considerRange(int from, int to) {
      for (var i = from; i < to && selected.length < maxWords; i++) {
        final cleaned = SherpaTokenVocab._cleanWord(scriptWords[i]);
        if (cleaned.length < 5) continue;
        final lower = cleaned.toLowerCase();
        if (_commonStopWords.contains(lower)) continue;
        if (seen.add(lower)) {
          selected.add(cleaned);
        }
      }
    }

    // Prioritize upcoming words first, then wrap around earlier script words.
    considerRange(safeStart, scriptWords.length);
    if (selected.length < maxWords && safeStart > 0) {
      considerRange(0, safeStart);
    }
    return selected;
  }

  /// Builds `sherpa-onnx` token-level hotwords lines for the given [vocab]
  /// and [locale] (`he_IL` or `en_US`).
  static SherpaHotwordsResult buildForVocab({
    required SherpaTokenVocab vocab,
    required List<String> words,
    required String locale,
    int maxWords = defaultMaxWords,
  }) {
    final preferEnglish = locale.toLowerCase().startsWith('en');
    final lines = <String>[];
    final seenLines = <String>{};

    for (final word in words) {
      if (lines.length >= maxWords) break;
      final hasHebrew = RegExp(r'[\u0590-\u05FF]').hasMatch(word);
      final hasLatin = RegExp(r'[A-Za-z]').hasMatch(word);
      if (preferEnglish && !hasLatin) continue;
      if (!preferEnglish && !hasHebrew && !hasLatin) continue;

      final tokenized = vocab.tokenizeWord(word);
      if (tokenized != null && seenLines.add(tokenized)) {
        lines.add(tokenized);
      }
    }

    return SherpaHotwordsResult(
      text: lines.join('\n'),
      wordCount: lines.length,
    );
  }
}
