import 'script_word.dart';

class Script {
  final String id;
  final String title;
  final String rawText;
  final List<ScriptWord> words;
  final bool isRtl;

  const Script({
    required this.id,
    required this.title,
    required this.rawText,
    required this.words,
    required this.isRtl,
  });

  Script copyWith({String? title, String? rawText, List<ScriptWord>? words, bool? isRtl}) {
    return Script(
      id: id,
      title: title ?? this.title,
      rawText: rawText ?? this.rawText,
      words: words ?? this.words,
      isRtl: isRtl ?? this.isRtl,
    );
  }

  bool get isEmpty => rawText.trim().isEmpty;
}
