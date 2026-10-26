import '../../../core/extensions/string_extensions.dart';

/// Remembers speech that already passed the movement policy. This may only
/// preserve context on a non-advancing result, never authorize movement or add
/// evidence. Unlike the script-based consumed guard, an imperfect earlier word
/// cannot turn a punctuation-only revision of accepted speech into an aside.
class SttAcceptedRevisionService {
  static const maxAge = Duration(seconds: 8);
  static const maxWords = 18;
  List<String> _words = const [];
  int? _target;
  DateTime? _acceptedAt;

  void reset() {
    _words = const [];
    _target = null;
    _acceptedAt = null;
  }

  void remember({
    required String transcript,
    required int target,
    required DateTime now,
  }) {
    final words = _normalize(transcript);
    _words =
        words.length > maxWords
            ? words.sublist(words.length - maxWords)
            : words;
    _target = target;
    _acceptedAt = now;
  }

  bool isRevision({
    required String transcript,
    required int currentIndex,
    required DateTime now,
  }) {
    final acceptedAt = _acceptedAt;
    if (_target != currentIndex || acceptedAt == null) return false;
    final age = now.difference(acceptedAt);
    if (age.isNegative || age > maxAge) return false;
    final words = _normalize(transcript);
    // Exact normalized suffix only: no changed words/numbers, fresh append,
    // prefix retraction, one-word repetition, or fuzzy matching permission.
    if (words.length < 2 || words.length > _words.length) return false;
    final offset = _words.length - words.length;
    for (var i = 0; i < words.length; i++) {
      if (words[i] != _words[offset + i]) return false;
    }
    return true;
  }

  List<String> _normalize(String text) => text
      .split(RegExp(r'\s+'))
      // Numeric punctuation can change meaning (20.22 vs 2022, -20 vs 20).
      // Be stricter than lexical punctuation cleanup for numeric tokens.
      .map(
        (word) =>
            RegExp(r'\d').hasMatch(word)
                ? word.toLowerCase()
                : word.normalizeForMatching(),
      )
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
}
