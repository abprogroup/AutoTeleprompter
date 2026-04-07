import 'script_word.dart';

class Script {
  final String id;
  final String title;
  final String rawText;
  final List<ScriptWord> words;
  final bool isRtl;
  final String sourceType; // 'TEMP', 'RTF', 'PDF', 'TXT', etc.
  final String sessionId;   // Unique session key for Deep Memory style recovery
  final String? historyJson; // Persisted Undo/Redo stack for v3.5.4
  final int historyIndex;     // v3.8 persistence

  const Script({
    required this.id,
    required this.title,
    required this.rawText,
    required this.words,
    required this.isRtl,
    this.sourceType = 'TEMP',
    required this.sessionId,
    this.historyJson,
    this.historyIndex = -1,
  });

  Script copyWith({
    String? title, 
    String? rawText, 
    List<ScriptWord>? words, 
    bool? isRtl, 
    String? sourceType, 
    String? sessionId,
    String? historyJson,
    int? historyIndex,
  }) {
    return Script(
      id: id,
      title: title ?? this.title,
      rawText: rawText ?? this.rawText,
      words: words ?? this.words,
      isRtl: isRtl ?? this.isRtl,
      sourceType: sourceType ?? this.sourceType,
      sessionId: sessionId ?? this.sessionId,
      historyJson: historyJson ?? this.historyJson,
      historyIndex: historyIndex ?? this.historyIndex,
    );
  }

  bool get isEmpty => rawText.trim().isEmpty;
}
