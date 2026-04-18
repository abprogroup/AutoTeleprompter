import 'dart:convert';

// v3.9.5.57: Extracted Editor State Model
class EditorState {
  final String text;
  final DateTime timestamp;
  final String description;
  final double fontSize;
  final String fontFamily;
  final double lineSpacing;
  final double letterSpacing;
  final double wordSpacing;
  final int scriptBgColor;
  final int currentWordColor;
  final int futureWordColor;
  final String textAlign;

  EditorState({
    required this.text,
    required this.timestamp,
    required this.description,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.scriptBgColor,
    required this.currentWordColor,
    required this.futureWordColor,
    required this.textAlign,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'description': description,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'lineSpacing': lineSpacing,
    'letterSpacing': letterSpacing,
    'wordSpacing': wordSpacing,
    'scriptBgColor': scriptBgColor,
    'currentWordColor': currentWordColor,
    'futureWordColor': futureWordColor,
    'textAlign': textAlign,
  };

  factory EditorState.fromJson(Map<String, dynamic> json) => EditorState(
    text: json['text'] as String,
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    description: json['description'] as String? ?? 'Edit',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 40.0,
    fontFamily: json['fontFamily'] as String? ?? 'Inter',
    lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.0,
    letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
    wordSpacing: (json['wordSpacing'] as num?)?.toDouble() ?? 0.0,
    scriptBgColor: json['scriptBgColor'] as int? ?? 0xFF000000,
    currentWordColor: json['currentWordColor'] as int? ?? 0xFFFFBF00,
    futureWordColor: json['futureWordColor'] as int? ?? 0xFFFFFFFF,
    textAlign: json['textAlign'] as String? ?? 'center',
  );
}
