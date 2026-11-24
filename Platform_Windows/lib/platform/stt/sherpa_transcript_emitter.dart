/// Helpers for formatting offline `sherpa-onnx` streaming & rolling transcripts
/// so they align smoothly with AutoTeleprompter's cumulative transcript buffer.
class SherpaTranscriptEmitter {
  SherpaTranscriptEmitter();

  List<String> _lastEmittedWords = const <String>[];

  void reset() {
    _lastEmittedWords = const <String>[];
  }

  /// Decides whether [text] should be emitted and whether it must set
  /// `isFinal: true` to rebase AutoTeleprompter's cumulative transcript buffer.
  ///
  /// - Punctuation-only updates (e.g. `"העולם"` -> `"העולם."`) produce identical
  ///   normalized words and are suppressed so already-read phrases are NEVER
  ///   replayed into a repeated later paragraph (like a second `"ברוך אתה ה'"`).
  /// - When an endpoint fires with the exact same words already emitted, it is
  ///   also suppressed so the stream can reset cleanly without replaying text.
  /// - When an earlier word's actual letters change (e.g. `"FAI"` -> `"FAITH"`
  ///   or Parakeet revising `"So shall we"` -> `"Social media"`), returning
  ///   `isFinal: true` lets `SttTranscriptBufferService` rebase the tail cleanly
  ///   instead of failing-closed and swallowing subsequent partials.
  ({String text, bool isFinal})? prepareEmission(
    String text, {
    required bool forceFinal,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final currentWords = _normalizeWords(trimmed);
    if (currentWords.isEmpty) return null;

    // Never re-emit if the spoken words didn't actually change (punctuation
    // additions or endpoint flushes of already-sent speech).
    if (_wordsEqual(currentWords, _lastEmittedWords)) {
      return null;
    }

    // Never emit a pure retraction/shrink that already matches our prefix.
    if (!forceFinal &&
        currentWords.length < _lastEmittedWords.length &&
        _startsWithWords(_lastEmittedWords, currentWords)) {
      return null;
    }

    final revisedEarlierWord =
        _lastEmittedWords.isNotEmpty &&
        !_startsWithWords(currentWords, _lastEmittedWords);

    _lastEmittedWords = currentWords;
    return (text: trimmed, isFinal: forceFinal || revisedEarlierWord);
  }

  static List<String> _normalizeWords(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '')
        .replaceAll(RegExp(r"[^\p{L}\p{N}\s']", unicode: true), ' ')
        .trim();
    if (cleaned.isEmpty) return const <String>[];
    return cleaned.split(RegExp(r'\s+')).toList(growable: false);
  }

  static bool _wordsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _startsWithWords(List<String> full, List<String> prefix) {
    if (full.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (full[i] != prefix[i]) return false;
    }
    return true;
  }
}
