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

  // v3.9.5.46: Absolute Metadata Parity
  final double fontSize;
  final String fontFamily;
  final double lineSpacing;
  final double letterSpacing;
  final double wordSpacing;
  final String textAlign;
  final int scriptBgColor;
  final int currentWordColor;
  final int futureWordColor;

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
    this.fontSize = 18,
    this.fontFamily = 'Inter',
    this.lineSpacing = 1.0,
    this.letterSpacing = 0.0,
    this.wordSpacing = 0.0,
    this.textAlign = 'center',
    this.scriptBgColor = 0xFF000000,
    this.currentWordColor = 0xFFFFBF00,
    this.futureWordColor = 0xFFFFFFFF,
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
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
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
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      textAlign: textAlign ?? this.textAlign,
      scriptBgColor: scriptBgColor ?? this.scriptBgColor,
      currentWordColor: currentWordColor ?? this.currentWordColor,
      futureWordColor: futureWordColor ?? this.futureWordColor,
    );
  }

  bool get isEmpty => rawText.trim().isEmpty;
}
