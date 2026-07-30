part of 'settings_provider.dart';

class AppSettings {
  static const String updateChannelStable = 'stable';
  static const String updateChannelBeta = 'beta';
  static const String updateChannelInternal = 'internal';
  static const String contentCreatorRecordingFormatMp4 = 'mp4';
  static const String contentCreatorRecordingFormatAudio = 'audio';
  static const String contentCreatorFeedStrip = 'strip';
  static const String contentCreatorFeedBubble = 'bubble';
  static const String contentCreatorFeedFull = 'full';
  static const String contentCreatorBubbleRectangle = 'rectangle';
  static const String contentCreatorBubbleRounded = 'rounded';
  static const String contentCreatorBubbleCircle = 'circle';

  // False until the async SharedPreferences load in SettingsNotifier._load()
  // completes. Gates any first-run/onboarding check that must not fire
  // against the pre-load default state (e.g. a fresh "seen version" of "").
  final bool settingsLoaded;
  final double fontSize;
  final String languageMode; // 'auto', 'he', 'en'
  final double scrollLead; // 0.2–0.5, viewport ratio for reading line
  final String lastScript;
  final String lastScriptTitle;
  final String lastScriptSessionId; // Points to the encrypted script record
  final String scrollMode; // 'auto' (speech) | 'manual' (timer)
  final double scrollSpeed; // words per minute for manual mode
  final String textAlign; // 'center' | 'left' | 'right'
  final bool mirrorHorizontal; // flip horizontally
  final bool mirrorVertical; // flip vertically
  final int flipRotation; // screen rotation: 0, 90, 180, 270 degrees
  final double lineSpacing; // 1.0–2.5
  final double wordSpacing; // extra spacing between words (px)
  final double letterSpacing; // extra spacing between letters (px)
  final int scriptBgColor; // ARGB int, default black
  final int currentWordColor; // ARGB int, default amber
  final int futureWordColor; // ARGB int, default white
  final double pastWordOpacity; // 0.0–0.6
  final bool debugMode; // technical mode for STT logs
  final bool showSoundLevelMeter; // Windows: mic input level meter overlay
  final String videoResolution; // '480p', '720p', '1080p'
  final bool
      contentCreatorRecordingControlsSpeech; // Windows: recording start/stop also starts/stops the STT session
  final String
      contentCreatorRecordingFormat; // 'mp4' (video) | 'audio' (mic-only, via record package)
  final String contentCreatorFeedMode; // 'strip' | 'bubble' | 'full'
  final String contentCreatorBubbleShape; // 'rectangle' | 'rounded' | 'circle'
  final double contentCreatorBubbleSize; // fraction of screen width
  final double contentCreatorBubbleOpacity;
  final double contentCreatorBubbleRoundness;
  final double contentCreatorCameraOpacity; // 'full' feed mode background dim
  final double contentCreatorFeedBlur;
  final double
      contentCreatorTextScrim; // 'full' feed mode text-legibility scrim
  final double
      contentCreatorVignetteIntensity; // 'strip' feed mode eye-contact vignette
  final String
      androidOnboardingVersionSeen; // gallery/editor first-run walkthrough version the user has dismissed
  final String
      androidPresenterOnboardingVersionSeen; // present-mode first-run walkthrough + STT setup wizard version the user has dismissed
  final String
      contentCreatorWalkthroughVersionSeen; // Content Creator first-run walkthrough version the user has dismissed
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
      sttInputDeviceId; // Optional platform audioinput deviceId, empty = system default
  final String sttInputDeviceLabel; // Display label for the selected mic
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
  final String sttReliabilityMode;
  final String updateChannel; // 'stable' | 'beta' | 'internal'
  final bool checkUpdatesOnStartup;

  static const String sttReliabilityStandard = 'standard';
  static const String sttReliabilityNoisyRoom = 'noisyRoom';

  static String normalizeSttReliabilityMode(String? mode) {
    switch (mode) {
      case sttReliabilityStandard:
      case sttReliabilityNoisyRoom:
        return mode!;
      default:
        return sttReliabilityStandard;
    }
  }

  const AppSettings({
    this.settingsLoaded = false,
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
    this.showSoundLevelMeter = false,
    this.videoResolution = '720p',
    this.contentCreatorRecordingControlsSpeech = false,
    this.contentCreatorRecordingFormat = contentCreatorRecordingFormatMp4,
    this.contentCreatorFeedMode = contentCreatorFeedStrip,
    this.contentCreatorBubbleShape = contentCreatorBubbleRounded,
    this.contentCreatorBubbleSize = 0.24,
    this.contentCreatorBubbleOpacity = 1.0,
    this.contentCreatorBubbleRoundness = 0.18,
    this.contentCreatorCameraOpacity = 0.72,
    this.contentCreatorFeedBlur = 14.0,
    this.contentCreatorTextScrim = 0.55,
    this.contentCreatorVignetteIntensity = 0.45,
    this.androidOnboardingVersionSeen = '',
    this.androidPresenterOnboardingVersionSeen = '',
    this.contentCreatorWalkthroughVersionSeen = '',
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
    this.sttReliabilityMode = sttReliabilityStandard,
    this.updateChannel = updateChannelStable,
    this.checkUpdatesOnStartup = false,
  });

  AppSettings copyWith({
    bool? settingsLoaded,
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
    bool? showSoundLevelMeter,
    String? videoResolution,
    bool? contentCreatorRecordingControlsSpeech,
    String? contentCreatorRecordingFormat,
    String? contentCreatorFeedMode,
    String? contentCreatorBubbleShape,
    double? contentCreatorBubbleSize,
    double? contentCreatorBubbleOpacity,
    double? contentCreatorBubbleRoundness,
    double? contentCreatorCameraOpacity,
    double? contentCreatorFeedBlur,
    double? contentCreatorTextScrim,
    double? contentCreatorVignetteIntensity,
    String? androidOnboardingVersionSeen,
    String? androidPresenterOnboardingVersionSeen,
    String? contentCreatorWalkthroughVersionSeen,
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
    String? sttReliabilityMode,
    String? updateChannel,
    bool? checkUpdatesOnStartup,
  }) {
    return AppSettings(
      settingsLoaded: settingsLoaded ?? this.settingsLoaded,
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
      showSoundLevelMeter: showSoundLevelMeter ?? this.showSoundLevelMeter,
      videoResolution: videoResolution ?? this.videoResolution,
      contentCreatorRecordingControlsSpeech:
          contentCreatorRecordingControlsSpeech ??
              this.contentCreatorRecordingControlsSpeech,
      contentCreatorRecordingFormat:
          contentCreatorRecordingFormat ?? this.contentCreatorRecordingFormat,
      contentCreatorFeedMode:
          contentCreatorFeedMode ?? this.contentCreatorFeedMode,
      contentCreatorBubbleShape:
          contentCreatorBubbleShape ?? this.contentCreatorBubbleShape,
      contentCreatorBubbleSize:
          contentCreatorBubbleSize ?? this.contentCreatorBubbleSize,
      contentCreatorBubbleOpacity:
          contentCreatorBubbleOpacity ?? this.contentCreatorBubbleOpacity,
      contentCreatorBubbleRoundness:
          contentCreatorBubbleRoundness ?? this.contentCreatorBubbleRoundness,
      contentCreatorCameraOpacity:
          contentCreatorCameraOpacity ?? this.contentCreatorCameraOpacity,
      contentCreatorFeedBlur:
          contentCreatorFeedBlur ?? this.contentCreatorFeedBlur,
      contentCreatorTextScrim:
          contentCreatorTextScrim ?? this.contentCreatorTextScrim,
      contentCreatorVignetteIntensity: contentCreatorVignetteIntensity ??
          this.contentCreatorVignetteIntensity,
      androidOnboardingVersionSeen:
          androidOnboardingVersionSeen ?? this.androidOnboardingVersionSeen,
      androidPresenterOnboardingVersionSeen:
          androidPresenterOnboardingVersionSeen ??
              this.androidPresenterOnboardingVersionSeen,
      contentCreatorWalkthroughVersionSeen:
          contentCreatorWalkthroughVersionSeen ??
              this.contentCreatorWalkthroughVersionSeen,
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
      sttReliabilityMode: sttReliabilityMode ?? this.sttReliabilityMode,
      updateChannel: updateChannel ?? this.updateChannel,
      checkUpdatesOnStartup:
          checkUpdatesOnStartup ?? this.checkUpdatesOnStartup,
    );
  }
}

String _normalizeSttReliabilityMode(String? mode) {
  return AppSettings.normalizeSttReliabilityMode(mode);
}
