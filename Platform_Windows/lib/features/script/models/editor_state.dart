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
  final int? focusBlockIndex;
  final int? selectionBaseOffset;
  final int? selectionExtentOffset;
  final bool appSelectionActive;
  final int? appSelectionStartBlock;
  final int? appSelectionStartOffset;
  final int? appSelectionEndBlock;
  final int? appSelectionEndOffset;
  final double? scrollOffset;

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
    this.focusBlockIndex,
    this.selectionBaseOffset,
    this.selectionExtentOffset,
    this.appSelectionActive = false,
    this.appSelectionStartBlock,
    this.appSelectionStartOffset,
    this.appSelectionEndBlock,
    this.appSelectionEndOffset,
    this.scrollOffset,
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
        if (focusBlockIndex != null) 'focusBlockIndex': focusBlockIndex,
        if (selectionBaseOffset != null)
          'selectionBaseOffset': selectionBaseOffset,
        if (selectionExtentOffset != null)
          'selectionExtentOffset': selectionExtentOffset,
        'appSelectionActive': appSelectionActive,
        if (appSelectionStartBlock != null)
          'appSelectionStartBlock': appSelectionStartBlock,
        if (appSelectionStartOffset != null)
          'appSelectionStartOffset': appSelectionStartOffset,
        if (appSelectionEndBlock != null)
          'appSelectionEndBlock': appSelectionEndBlock,
        if (appSelectionEndOffset != null)
          'appSelectionEndOffset': appSelectionEndOffset,
        if (scrollOffset != null) 'scrollOffset': scrollOffset,
      };

  factory EditorState.fromJson(Map<String, dynamic> json) => EditorState(
        text: json['text'] as String,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
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
        focusBlockIndex: json['focusBlockIndex'] as int?,
        selectionBaseOffset: json['selectionBaseOffset'] as int?,
        selectionExtentOffset: json['selectionExtentOffset'] as int?,
        appSelectionActive: json['appSelectionActive'] as bool? ?? false,
        appSelectionStartBlock: json['appSelectionStartBlock'] as int?,
        appSelectionStartOffset: json['appSelectionStartOffset'] as int?,
        appSelectionEndBlock: json['appSelectionEndBlock'] as int?,
        appSelectionEndOffset: json['appSelectionEndOffset'] as int?,
        scrollOffset: (json['scrollOffset'] as num?)?.toDouble(),
      );
}
