import '../../../core/extensions/string_extensions.dart';
import '../../script/models/script_word.dart';
import 'word_aligner.dart';

/// Recognizer revisions of an already-read phrase are not off-script speech.
/// Only an ordered suffix ending at the accepted position qualifies; no
/// forward search, numeric guessing, or new-word evidence is introduced here.
class SttConsumedSpeechService {
  const SttConsumedSpeechService();

  bool isConsumed({
    required List<ScriptWord> script,
    required String transcript,
    required int confirmedIndex,
    bool strict = false,
  }) {
    final heard =
        transcript
            .split(RegExp(r'\s+'))
            .map((word) => word.normalizeForMatching())
            .where((word) => word.isNotEmpty)
            .toList();
    // One word may legitimately repeat ("very very"). It cannot establish
    // that an entire recognizer result is an already-consumed revision.
    if (heard.length < 2 ||
        heard.length > 18 ||
        confirmedIndex < 0 ||
        confirmedIndex >= script.length) {
      return false;
    }
    var cursor = confirmedIndex;
    for (final word in heard.reversed) {
      while (cursor >= 0 &&
          (script[cursor].isNewline || script[cursor].normalized.isEmpty)) {
        cursor--;
      }
      if (cursor < 0) return false;
      final expected = script[cursor];
      if (word != expected.normalized) {
        if (RegExp(r'\d').hasMatch('$word ${expected.normalized}')) {
          return false;
        }
        final similarity = WordAligner.spokenWordSimilarity(word, expected);
        if (similarity < (strict || heard.length == 1 ? 0.82 : 0.70)) {
          return false;
        }
      }
      cursor--;
    }
    return true;
  }
}
