class AppSettings {
  static const String sttEngineAuto = 'windows_auto';
  static const String sttEngineWindowsOffline = 'windows_offline';
  static const String sttEngineBrowserOnline = 'browser_online';
  static const String importColorModePrompter = 'prompter_contrast';
  static const String importColorModeDocument = 'document_original';
  static const String updateChannelStable = 'stable';
  static const String updateChannelBeta = 'beta';
  static const String updateChannelInternal = 'internal';
  static const String languageModeAuto = 'auto';
  static const String languageModeHebrew = 'he';
  static const String languageModeEnglish = 'en';
  static const String contentCreatorSourceNative = 'native';
  static const String contentCreatorSourceUsb = 'usb';
  static const String contentCreatorSourceVirtual = 'virtual';
  static const String contentCreatorSourceAll = 'all';
  static const String contentCreatorLayoutReading = 'reading';
  static const String contentCreatorLayoutBalanced = 'balanced';
  static const String contentCreatorLayoutCamera = 'camera';
  static const String contentCreatorFeedBubble = 'bubble';
  static const String contentCreatorFeedFull = 'full';
  static const String contentCreatorBubbleBottomRight = 'bottomRight';
  static const String contentCreatorBubbleBottomLeft = 'bottomLeft';
  static const String contentCreatorBubbleTopRight = 'topRight';
  static const String contentCreatorBubbleTopLeft = 'topLeft';
  static const String contentCreatorBubbleShapeRectangle = 'rectangle';
  static const String contentCreatorBubbleShapeRounded = 'rounded';
  static const String contentCreatorBubbleShapeCircle = 'circle';
  static const String contentCreatorBubbleShapeTriangle = 'triangle';
  static const String contentCreatorRecordingFormatMp4 = 'mp4';
  static const String contentCreatorRecordingFormatWebm = 'webm';
  static const String contentCreatorRecordingFormatMovProRes = 'mov_prores';
  static const String contentCreatorRecordingFormatWav = 'wav';
  static const String contentCreatorRecordingAudioCamera = 'camera_audio';
  // Legacy persisted value from the removed soundless-video beta option.
  // Normalizers keep old installs on camera audio; no active UI should expose it.
  static const String contentCreatorRecordingAudioSilent = 'silent_video';
  static const String manualScrollBarBottom = 'bottom';
  static const String manualScrollBarTop = 'top';
  static const String manualScrollBarLeft = 'left';
  static const String manualScrollBarRight = 'right';

  static String normalizeSttEngine(String? engine) {
    switch (engine) {
      case sttEngineAuto:
      case sttEngineWindowsOffline:
      case sttEngineBrowserOnline:
        return engine!;
      case 'google':
      case null:
        return sttEngineAuto;
      default:
        return sttEngineAuto;
    }
  }

  static String normalizeLanguageMode(String? mode) {
    switch (mode) {
      case languageModeAuto:
      case languageModeHebrew:
      case languageModeEnglish:
        return mode!;
      default:
        return languageModeAuto;
    }
  }

  final double fontSize;
  final String languageMode; // 'auto', 'he', 'en'
  final double scrollLead; // 0.2-0.5, viewport ratio for reading line
  final String lastScript;
  final String lastScriptTitle;
  final String lastScriptSessionId;
  final String scrollMode; // 'auto' (speech) | 'manual' (timer)
  final double scrollSpeed; // words per minute for manual mode
  final String textAlign; // 'center' | 'left' | 'right'
  final bool mirrorHorizontal; // flip horizontally
  final bool mirrorVertical; // flip vertically
  final int flipRotation; // screen rotation: 0, 90, 180, 270 degrees
  final double lineSpacing; // 1.0-2.5
  final double wordSpacing; // extra spacing between words (px)
  final double letterSpacing; // extra spacing between letters (px)
  final int scriptBgColor; // ARGB int, default black
  final int currentWordColor; // ARGB int, default amber
  final int futureWordColor; // ARGB int, default white
  final double pastWordOpacity; // 0.05-1.0
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
  final String sttEngine; // Windows: auto/offline/browser, legacy 'google'
  final bool allowScrollDuringActiveSession;
  final String manualScrollBarPlacement;
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
  final String contentCreatorCameraSourceMode;
  final String contentCreatorLayoutPreset;
  final double contentCreatorCameraOpacity;
  final String contentCreatorFeedMode;
  final String contentCreatorBubblePosition;
  final String contentCreatorBubbleShape;
  final double contentCreatorBubbleSize;
  final double contentCreatorBubbleOpacity;
  final double contentCreatorBubbleRoundness;
  final double contentCreatorBubbleOffsetX;
  final double contentCreatorBubbleOffsetY;
  final double contentCreatorVignetteIntensity;
  final double contentCreatorFeedBlur;
  final double contentCreatorTextScrim;
  final String contentCreatorRecordingFolder;
  final String contentCreatorRecordingFormat;
  final String contentCreatorRecordingAudioMode;
  final String importColorMode;
  final bool reduceMotion;
  final double uiScale;
  final String updateChannel;

  const AppSettings({
    this.fontSize = 20.0,
    this.languageMode = languageModeAuto,
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
    this.pastWordOpacity = 0.3,
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
    this.sttEngine = sttEngineAuto,
    this.allowScrollDuringActiveSession = false,
    this.manualScrollBarPlacement = manualScrollBarBottom,
    this.readFadeIntensity = 0.0,
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
    this.contentCreatorCameraSourceMode = contentCreatorSourceNative,
    this.contentCreatorLayoutPreset = contentCreatorLayoutReading,
    this.contentCreatorCameraOpacity = 0.72,
    this.contentCreatorFeedMode = contentCreatorFeedBubble,
    this.contentCreatorBubblePosition = contentCreatorBubbleBottomRight,
    this.contentCreatorBubbleShape = contentCreatorBubbleShapeRounded,
    this.contentCreatorBubbleSize = 0.24,
    this.contentCreatorBubbleOpacity = 1.0,
    this.contentCreatorBubbleRoundness = 0.18,
    this.contentCreatorBubbleOffsetX = 0.0,
    this.contentCreatorBubbleOffsetY = 0.0,
    this.contentCreatorVignetteIntensity = 0.45,
    this.contentCreatorFeedBlur = 14.0,
    this.contentCreatorTextScrim = 0.55,
    this.contentCreatorRecordingFolder = '',
    this.contentCreatorRecordingFormat = contentCreatorRecordingFormatMp4,
    this.contentCreatorRecordingAudioMode = contentCreatorRecordingAudioCamera,
    this.importColorMode = importColorModePrompter,
    this.reduceMotion = false,
    this.uiScale = 1.0,
    this.updateChannel = updateChannelStable,
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
    bool? allowScrollDuringActiveSession,
    String? manualScrollBarPlacement,
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
    String? contentCreatorCameraSourceMode,
    String? contentCreatorLayoutPreset,
    double? contentCreatorCameraOpacity,
    String? contentCreatorFeedMode,
    String? contentCreatorBubblePosition,
    String? contentCreatorBubbleShape,
    double? contentCreatorBubbleSize,
    double? contentCreatorBubbleOpacity,
    double? contentCreatorBubbleRoundness,
    double? contentCreatorBubbleOffsetX,
    double? contentCreatorBubbleOffsetY,
    double? contentCreatorVignetteIntensity,
    double? contentCreatorFeedBlur,
    double? contentCreatorTextScrim,
    String? contentCreatorRecordingFolder,
    String? contentCreatorRecordingFormat,
    String? contentCreatorRecordingAudioMode,
    String? importColorMode,
    bool? reduceMotion,
    double? uiScale,
    String? updateChannel,
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
      allowScrollDuringActiveSession:
          allowScrollDuringActiveSession ?? this.allowScrollDuringActiveSession,
      manualScrollBarPlacement:
          manualScrollBarPlacement ?? this.manualScrollBarPlacement,
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
      contentCreatorCameraSourceMode:
          contentCreatorCameraSourceMode ?? this.contentCreatorCameraSourceMode,
      contentCreatorLayoutPreset:
          contentCreatorLayoutPreset ?? this.contentCreatorLayoutPreset,
      contentCreatorCameraOpacity:
          contentCreatorCameraOpacity ?? this.contentCreatorCameraOpacity,
      contentCreatorFeedMode:
          contentCreatorFeedMode ?? this.contentCreatorFeedMode,
      contentCreatorBubblePosition:
          contentCreatorBubblePosition ?? this.contentCreatorBubblePosition,
      contentCreatorBubbleShape:
          contentCreatorBubbleShape ?? this.contentCreatorBubbleShape,
      contentCreatorBubbleSize:
          contentCreatorBubbleSize ?? this.contentCreatorBubbleSize,
      contentCreatorBubbleOpacity:
          contentCreatorBubbleOpacity ?? this.contentCreatorBubbleOpacity,
      contentCreatorBubbleRoundness:
          contentCreatorBubbleRoundness ?? this.contentCreatorBubbleRoundness,
      contentCreatorBubbleOffsetX:
          contentCreatorBubbleOffsetX ?? this.contentCreatorBubbleOffsetX,
      contentCreatorBubbleOffsetY:
          contentCreatorBubbleOffsetY ?? this.contentCreatorBubbleOffsetY,
      contentCreatorVignetteIntensity: contentCreatorVignetteIntensity ??
          this.contentCreatorVignetteIntensity,
      contentCreatorFeedBlur:
          contentCreatorFeedBlur ?? this.contentCreatorFeedBlur,
      contentCreatorTextScrim:
          contentCreatorTextScrim ?? this.contentCreatorTextScrim,
      contentCreatorRecordingFolder:
          contentCreatorRecordingFolder ?? this.contentCreatorRecordingFolder,
      contentCreatorRecordingFormat:
          contentCreatorRecordingFormat ?? this.contentCreatorRecordingFormat,
      contentCreatorRecordingAudioMode: contentCreatorRecordingAudioMode ??
          this.contentCreatorRecordingAudioMode,
      importColorMode: importColorMode ?? this.importColorMode,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      uiScale: uiScale ?? this.uiScale,
      updateChannel: updateChannel ?? this.updateChannel,
    );
  }
}
