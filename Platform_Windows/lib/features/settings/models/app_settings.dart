class AppSettings {
  final double fontSize;
  final String languageMode; // 'auto', 'he', 'en'
  final double scrollLead; // 0.2â€“0.5, viewport ratio for reading line
  final String lastScript;
  final String lastScriptTitle;
  final String lastScriptSessionId;
  final String scrollMode; // 'auto' (speech) | 'manual' (timer)
  final double scrollSpeed; // words per minute for manual mode
  final String textAlign; // 'center' | 'left' | 'right'
  final bool mirrorHorizontal; // flip horizontally
  final bool mirrorVertical; // flip vertically
  final int flipRotation; // screen rotation: 0, 90, 180, 270 degrees
  final double lineSpacing; // 1.0â€“2.5
  final double wordSpacing; // extra spacing between words (px)
  final double letterSpacing; // extra spacing between letters (px)
  final int scriptBgColor; // ARGB int, default black
  final int currentWordColor; // ARGB int, default amber
  final int futureWordColor; // ARGB int, default white
  final double pastWordOpacity; // 0.0â€“0.6
  final bool debugMode; // technical mode for STT logs
  final String videoResolution; // '480p', '720p', '1080p'
  final List<String> recentScripts; // JSON strings of script metadata
  final String displayName; // User's name
  final int lastTextColor; // Persisted selection color
  final int lastHighlightColor; // Persisted selection highlight
  final String lastImportPath; // Persisted folder path for importer
  final int lastHistoryIndex; // v3.8 persistence
  final bool showCurrentWordHighlight; // v3.9.5 toggle
  final bool showUpcomingWordColor; // v3.9.5 toggle (default off)
  final String fontFamily; // v3.9.5.46
  final bool
      showAlignmentOverride; // v3.9.8 toggle for presentation alignment override
  final String sttEngine; // v4.0: 'google', 'whisper_base', 'whisper_small'
  final double
      readFadeIntensity; // v4.1: gradient fade for read text (0.0=off, 1.0=full)
  final String
      sttInputDeviceId; // Windows: WebView2 audioinput deviceId, empty = system default
  final String
      sttInputDeviceLabel; // Windows: display label for the selected mic
  final bool
      sttVisibleSkipEnabled; // Windows: allow STT to skip only to visible words
  final bool
      sttStrictBulletMode; // Windows: stricter STT for bullet/header prompting
  final bool
      sttHardVisibleSkipEnabled; // Windows: stricter visible-skip confirmation
  final bool
      sttManualProfileEnabled; // Windows: custom STT recognition thresholds
  final int sttManualStartAdvanceSmallWords;
  final int sttManualStartAdvanceBigWords;
  final int sttManualSafetySmallWords;
  final int sttManualSafetyBigWords;
  final int sttManualVisibleSkipSmallWords; // 0 = Off
  final int sttManualVisibleSkipBigWords; // 0 = Off
  final int sttManualBigWordMinLetters;

  const AppSettings({
    this.fontSize = 20.0,
    this.languageMode = 'auto',
    this.scrollLead = 0.32,
    this.lastScript = '',
    this.lastScriptTitle = '',
    this.lastScriptSessionId = '',
    this.scrollMode = 'auto',
    this.scrollSpeed = 100.0,
    this.textAlign = 'center',
    this.mirrorHorizontal = false,
    this.mirrorVertical = false,
    this.flipRotation = 0,
    this.lineSpacing = 1.2,
    this.wordSpacing = 0.0, // default: no extra word spacing
    this.letterSpacing = 0.0, // default: no extra letter spacing
    this.scriptBgColor = 0xFF000000,
    this.currentWordColor = 0xFFFFBF00,
    this.futureWordColor = 0xFFFFFFFF,
    this.pastWordOpacity = 0.7,
    this.debugMode = false,
    this.videoResolution = '720p',
    this.recentScripts = const [],
    this.displayName = 'Guest',
    this.lastTextColor = 0xFFFFBF00,
    this.lastHighlightColor = 0x4DFFFFFF,
    this.lastImportPath = '',
    this.lastHistoryIndex = -1,
    this.showCurrentWordHighlight = false,
    this.showUpcomingWordColor = false,
    this.fontFamily = 'Inter',
    this.showAlignmentOverride = false,
    this.sttEngine = 'google',
    this.readFadeIntensity = 1.0,
    this.sttInputDeviceId = '',
    this.sttInputDeviceLabel = 'System default microphone',
    this.sttVisibleSkipEnabled = false,
    this.sttStrictBulletMode = false,
    this.sttHardVisibleSkipEnabled = false,
    this.sttManualProfileEnabled = false,
    this.sttManualStartAdvanceSmallWords = 4,
    this.sttManualStartAdvanceBigWords = 3,
    this.sttManualSafetySmallWords = 2,
    this.sttManualSafetyBigWords = 1,
    this.sttManualVisibleSkipSmallWords = 0,
    this.sttManualVisibleSkipBigWords = 0,
    this.sttManualBigWordMinLetters = 5,
  });

  AppSettings copyWith({
    double? fontSize,
    String? languageMode,
    double? scrollLead,
    String? lastScript,
    String? lastScriptTitle,
    String? lastScriptSessionId,
    String? scrollMode,
    double? scrollSpeed,
    String? textAlign,
    bool? mirrorHorizontal,
    bool? mirrorVertical,
    int? flipRotation,
    double? lineSpacing,
    double? wordSpacing,
    double? letterSpacing,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    double? pastWordOpacity,
    bool? debugMode,
    String? videoResolution,
    List<String>? recentScripts,
    String? displayName,
    int? lastTextColor,
    int? lastHighlightColor,
    String? lastImportPath,
    int? lastHistoryIndex,
    bool? showCurrentWordHighlight,
    bool? showUpcomingWordColor,
    String? fontFamily,
    bool? showAlignmentOverride,
    String? sttEngine,
    double? readFadeIntensity,
    String? sttInputDeviceId,
    String? sttInputDeviceLabel,
    bool? sttVisibleSkipEnabled,
    bool? sttStrictBulletMode,
    bool? sttHardVisibleSkipEnabled,
    bool? sttManualProfileEnabled,
    int? sttManualStartAdvanceSmallWords,
    int? sttManualStartAdvanceBigWords,
    int? sttManualSafetySmallWords,
    int? sttManualSafetyBigWords,
    int? sttManualVisibleSkipSmallWords,
    int? sttManualVisibleSkipBigWords,
    int? sttManualBigWordMinLetters,
  }) {
    return AppSettings(
      fontSize: fontSize ?? this.fontSize,
      languageMode: languageMode ?? this.languageMode,
      scrollLead: scrollLead ?? this.scrollLead,
      lastScript: lastScript ?? this.lastScript,
      lastScriptTitle: lastScriptTitle ?? this.lastScriptTitle,
      lastScriptSessionId: lastScriptSessionId ?? this.lastScriptSessionId,
      scrollMode: scrollMode ?? this.scrollMode,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      textAlign: textAlign ?? this.textAlign,
      mirrorHorizontal: mirrorHorizontal ?? this.mirrorHorizontal,
      mirrorVertical: mirrorVertical ?? this.mirrorVertical,
      flipRotation: flipRotation ?? this.flipRotation,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      wordSpacing: wordSpacing ?? this.wordSpacing,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      scriptBgColor: scriptBgColor ?? this.scriptBgColor,
      currentWordColor: currentWordColor ?? this.currentWordColor,
      futureWordColor: futureWordColor ?? this.futureWordColor,
      pastWordOpacity: pastWordOpacity ?? this.pastWordOpacity,
      debugMode: debugMode ?? this.debugMode,
      videoResolution: videoResolution ?? this.videoResolution,
      recentScripts: recentScripts ?? this.recentScripts,
      displayName: displayName ?? this.displayName,
      lastTextColor: lastTextColor ?? this.lastTextColor,
      lastHighlightColor: lastHighlightColor ?? this.lastHighlightColor,
      lastImportPath: lastImportPath ?? this.lastImportPath,
      lastHistoryIndex: lastHistoryIndex ?? this.lastHistoryIndex,
      showCurrentWordHighlight:
          showCurrentWordHighlight ?? this.showCurrentWordHighlight,
      showUpcomingWordColor:
          showUpcomingWordColor ?? this.showUpcomingWordColor,
      fontFamily: fontFamily ?? this.fontFamily,
      showAlignmentOverride:
          showAlignmentOverride ?? this.showAlignmentOverride,
      sttEngine: sttEngine ?? this.sttEngine,
      readFadeIntensity: readFadeIntensity ?? this.readFadeIntensity,
      sttInputDeviceId: sttInputDeviceId ?? this.sttInputDeviceId,
      sttInputDeviceLabel: sttInputDeviceLabel ?? this.sttInputDeviceLabel,
      sttVisibleSkipEnabled:
          sttVisibleSkipEnabled ?? this.sttVisibleSkipEnabled,
      sttStrictBulletMode: sttStrictBulletMode ?? this.sttStrictBulletMode,
      sttHardVisibleSkipEnabled:
          sttHardVisibleSkipEnabled ?? this.sttHardVisibleSkipEnabled,
      sttManualProfileEnabled:
          sttManualProfileEnabled ?? this.sttManualProfileEnabled,
      sttManualStartAdvanceSmallWords: sttManualStartAdvanceSmallWords ??
          this.sttManualStartAdvanceSmallWords,
      sttManualStartAdvanceBigWords:
          sttManualStartAdvanceBigWords ?? this.sttManualStartAdvanceBigWords,
      sttManualSafetySmallWords:
          sttManualSafetySmallWords ?? this.sttManualSafetySmallWords,
      sttManualSafetyBigWords:
          sttManualSafetyBigWords ?? this.sttManualSafetyBigWords,
      sttManualVisibleSkipSmallWords:
          sttManualVisibleSkipSmallWords ?? this.sttManualVisibleSkipSmallWords,
      sttManualVisibleSkipBigWords:
          sttManualVisibleSkipBigWords ?? this.sttManualVisibleSkipBigWords,
      sttManualBigWordMinLetters:
          sttManualBigWordMinLetters ?? this.sttManualBigWordMinLetters,
    );
  }
}
