part of 'settings_provider.dart';

mixin SettingsNotifierAppearance on Notifier<AppSettings> {
  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    state = state.copyWith(fontSize: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, clamped);
  }

  Future<void> setLanguageMode(String mode) async {
    final normalized = _normalizeLanguageMode(mode);
    state = state.copyWith(languageMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, normalized);
  }

  Future<void> setScrollLead(double lead) async {
    final normalized = _normalizeScrollLead(lead);
    state = state.copyWith(scrollLead: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollLeadKey, normalized);
  }

  Future<void> setScrollMode(String mode) async {
    final normalized = _normalizeScrollMode(mode);
    state = state.copyWith(scrollMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scrollModeKey, normalized);
  }

  Future<void> setScrollSpeed(double speed) async {
    final normalized = _normalizeScrollSpeed(speed);
    state = state.copyWith(scrollSpeed: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollSpeedKey, normalized);
  }

  Future<void> setManualScrollBarPlacement(String placement) async {
    final normalized = _normalizeManualScrollBarPlacement(placement);
    state = state.copyWith(manualScrollBarPlacement: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_manualScrollBarPlacementKey, normalized);
  }

  Future<void> setTextAlign(String align) async {
    final normalized = _normalizeTextAlign(align);
    state = state.copyWith(textAlign: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textAlignKey, normalized);
  }

  Future<void> setMirrorHorizontal(bool mirror) async {
    state = state.copyWith(mirrorHorizontal: mirror);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mirrorHorizontalKey, mirror);
  }

  Future<void> setMirrorVertical(bool flip) async {
    state = state.copyWith(mirrorVertical: flip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_mirrorVerticalKey, flip);
  }

  Future<void> setFlipRotation(int degrees) async {
    final normalized = _normalizeFlipRotation(degrees);
    state = state.copyWith(flipRotation: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_flipRotationKey, normalized);
  }

  Future<void> setLineSpacing(double spacing) async {
    final clamped = _normalizeLineSpacing(spacing);
    state = state.copyWith(lineSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineSpacingKey, clamped);
  }

  Future<void> setWordSpacing(double spacing) async {
    final normalized = _normalizeWordSpacing(spacing);
    state = state.copyWith(wordSpacing: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wordSpacingKey, normalized);
  }

  Future<void> setLetterSpacing(double spacing) async {
    final normalized = _normalizeLetterSpacing(spacing);
    state = state.copyWith(letterSpacing: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_letterSpacingKey, normalized);
  }

  Future<void> setScriptBgColor(int color) async {
    final normalized = _normalizeColor(color, state.scriptBgColor);
    state = state.copyWith(scriptBgColor: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, normalized);
  }

  Future<void> setCurrentWordColor(int color) async {
    final normalized = _normalizeColor(color, state.currentWordColor);
    state = state.copyWith(currentWordColor: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentWordColorKey, normalized);
  }

  Future<void> setFutureWordColor(int color) async {
    final normalized = _normalizeColor(color, state.futureWordColor);
    state = state.copyWith(futureWordColor: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_futureWordColorKey, normalized);
  }

  Future<void> setPastWordOpacity(double opacity) async {
    final normalized = _normalizePastWordOpacity(opacity);
    state = state.copyWith(pastWordOpacity: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pastWordOpacityKey, normalized);
  }

  Future<void> toggleDebugMode() async {
    final newVal = !state.debugMode;
    state = state.copyWith(debugMode: newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, newVal);
  }

  Future<void> setShowSoundLevelMeter(bool enabled) async {
    state = state.copyWith(showSoundLevelMeter: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showSoundLevelMeterKey, enabled);
  }

  Future<void> setVideoResolution(String resolution) async {
    final normalized = _normalizeVideoResolution(resolution);
    state = state.copyWith(videoResolution: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoResolutionKey, normalized);
  }

  Future<void> setContentCreatorCameraSourceMode(String mode) async {
    final normalized = _normalizeContentCreatorCameraSource(mode);
    state = state.copyWith(contentCreatorCameraSourceMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorCameraSourceModeKey, normalized);
  }

  Future<void> setDefaultCameraDeviceName(String name) async {
    final normalized = name.trim();
    state = state.copyWith(defaultCameraDeviceName: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultCameraDeviceNameKey, normalized);
  }

  Future<void> setContentCreatorLayoutPreset(String preset) async {
    final normalized = _normalizeContentCreatorLayout(preset);
    state = state.copyWith(contentCreatorLayoutPreset: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorLayoutPresetKey, normalized);
  }

  Future<void> setContentCreatorCameraOpacity(double opacity) async {
    final clamped = opacity.clamp(0.2, 1.0).toDouble();
    state = state.copyWith(contentCreatorCameraOpacity: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorCameraOpacityKey, clamped);
  }

  Future<void> setContentCreatorFeedMode(String mode) async {
    final normalized = _normalizeContentCreatorFeedMode(mode);
    state = state.copyWith(contentCreatorFeedMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorFeedModeKey, normalized);
  }

  Future<void> setContentCreatorBubblePosition(String position) async {
    final normalized = _normalizeContentCreatorBubblePosition(position);
    state = state.copyWith(contentCreatorBubblePosition: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorBubblePositionKey, normalized);
  }

  Future<void> setContentCreatorBubbleShape(String shape) async {
    final normalized = _normalizeContentCreatorBubbleShape(shape);
    state = state.copyWith(contentCreatorBubbleShape: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorBubbleShapeKey, normalized);
  }

  Future<void> setContentCreatorBubbleSize(double size) async {
    final clamped = size.clamp(0.04, 0.60).toDouble();
    state = state.copyWith(contentCreatorBubbleSize: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorBubbleSizeKey, clamped);
  }

  Future<void> setContentCreatorBubbleOpacity(double opacity) async {
    final clamped = opacity.clamp(0.25, 1.0).toDouble();
    state = state.copyWith(contentCreatorBubbleOpacity: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorBubbleOpacityKey, clamped);
  }

  Future<void> setContentCreatorBubbleRoundness(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    state = state.copyWith(contentCreatorBubbleRoundness: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorBubbleRoundnessKey, clamped);
  }

  Future<void> setContentCreatorBubbleOffsetX(double value) async {
    final clamped = value.clamp(-0.25, 0.25).toDouble();
    state = state.copyWith(contentCreatorBubbleOffsetX: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorBubbleOffsetXKey, clamped);
  }

  Future<void> setContentCreatorBubbleOffsetY(double value) async {
    final clamped = value.clamp(-0.25, 0.25).toDouble();
    state = state.copyWith(contentCreatorBubbleOffsetY: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorBubbleOffsetYKey, clamped);
  }

  Future<void> setContentCreatorVignetteIntensity(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    state = state.copyWith(contentCreatorVignetteIntensity: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorVignetteIntensityKey, clamped);
  }

  Future<void> setContentCreatorFeedBlur(double value) async {
    final clamped = value.clamp(0.0, 30.0).toDouble();
    state = state.copyWith(contentCreatorFeedBlur: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorFeedBlurKey, clamped);
  }

  Future<void> setContentCreatorTextScrim(double value) async {
    final clamped = value.clamp(0.0, 0.9).toDouble();
    state = state.copyWith(contentCreatorTextScrim: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_contentCreatorTextScrimKey, clamped);
  }

  Future<void> setContentCreatorRecordingFolder(String folder) async {
    final normalized = _normalizeLocalPath(folder);
    state = state.copyWith(contentCreatorRecordingFolder: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingFolderKey, normalized);
  }

  Future<void> setContentCreatorRecordingFormat(String format) async {
    final normalized = _normalizeContentCreatorRecordingFormat(format);
    state = state.copyWith(contentCreatorRecordingFormat: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingFormatKey, normalized);
  }

  Future<void> setContentCreatorRecordingAudioMode(String mode) async {
    final normalized = _normalizeContentCreatorRecordingAudioMode(mode);
    state = state.copyWith(contentCreatorRecordingAudioMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingAudioModeKey, normalized);
  }

  Future<void> setContentCreatorRecordingControlsSpeech(bool enabled) async {
    state = state.copyWith(contentCreatorRecordingControlsSpeech: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contentCreatorRecordingControlsSpeechKey, enabled);
  }

  Future<void> setImportColorMode(String mode) async {
    final normalized = _normalizeImportColorMode(mode);
    state = state.copyWith(importColorMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_importColorModeKey, normalized);
  }

  Future<void> setReduceMotion(bool enabled) async {
    state = state.copyWith(reduceMotion: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceMotionKey, enabled);
  }

  Future<void> setUiScale(double scale) async {
    final normalized = _normalizeUiScale(scale);
    state = state.copyWith(uiScale: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_uiScaleKey, normalized);
  }

  Future<void> setUpdateChannel(String channel) async {
    final normalized = _normalizeUpdateChannel(channel, allowInternal: true);
    state = state.copyWith(updateChannel: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updateChannelKey, normalized);
  }

  Future<void> setCheckUpdatesOnStartup(bool enabled) async {
    state = state.copyWith(checkUpdatesOnStartup: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_checkUpdatesOnStartupKey, enabled);
  }

  Future<void> setCloudAutoSyncOnSave(bool enabled) async {
    state = state.copyWith(cloudAutoSyncOnSave: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudAutoSyncOnSaveKey, enabled);
  }

  Future<void> setSyncDeletedScriptsFolder(bool enabled) async {
    state = state.copyWith(syncDeletedScriptsFolder: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncDeletedScriptsFolderKey, enabled);
  }

  Future<void> setRecordingAutoBackup(bool enabled) async {
    state = state.copyWith(recordingAutoBackup: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_recordingAutoBackupKey, enabled);
  }

  Future<void> setMacOnboardingVersionSeen(String version) async {
    final normalized = version.trim();
    state = state.copyWith(macOnboardingVersionSeen: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macOnboardingVersionSeenKey, normalized);
  }

  Future<void> setDisplayName(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    state = state.copyWith(displayName: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, normalized);
  }

  Future<void> seedDisplayNameFromEmail(String email) async {
    final prefix = email.split('@').first.trim();
    if (prefix.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final savedName = (prefs.getString(_displayNameKey) ?? '').trim();
    final effectiveName =
        savedName.isNotEmpty ? savedName : state.displayName.trim();
    if (effectiveName.isNotEmpty && effectiveName.toLowerCase() != 'guest') {
      if (state.displayName != effectiveName) {
        state = state.copyWith(displayName: effectiveName);
      }
      return;
    }

    state = state.copyWith(displayName: prefix);
    await prefs.setString(_displayNameKey, prefix);
  }

  Future<void> resetDisplayNameToGuest() async {
    state = state.copyWith(displayName: 'Guest');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, 'Guest');
  }

  Future<void> setLastChosenTextColor(int color) async {
    state = state.copyWith(lastTextColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastTextColorKey, color);
  }

  Future<void> setLastChosenHighlightColor(int color) async {
    state = state.copyWith(lastHighlightColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastHighlightColorKey, color);
  }

  Future<void> resetToDefaultAppearance() async {
    state = state.copyWith(
      scriptBgColor: 0xFF000000,
      currentWordColor: 0xFFFFBF00,
      futureWordColor: 0xFFFFFFFF,
      lineSpacing: 1.2,
      wordSpacing: 0.0,
      letterSpacing: 0.0,
      fontSize: 18.0,
      fontFamily: 'Inter',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, 0xFF000000);
    await prefs.setInt(_currentWordColorKey, 0xFFFFBF00);
    await prefs.setInt(_futureWordColorKey, 0xFFFFFFFF);
    await prefs.setDouble(_lineSpacingKey, 1.2);
    await prefs.setDouble(_wordSpacingKey, 0.0);
    await prefs.setDouble(_letterSpacingKey, 0.0);
    await prefs.setDouble(_fontSizeKey, 18.0);
    await prefs.setString(_fontFamilyKey, 'Inter');
  }

  Future<void> setDocumentImportAppearance({int? scriptBgColor}) async {
    final normalizedBg = _normalizeColor(scriptBgColor, 0xFFFFFFFF);
    state = state.copyWith(
      scriptBgColor: normalizedBg,
      currentWordColor: 0xFFFFBF00,
      futureWordColor: 0xFF000000,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, normalizedBg);
    await prefs.setInt(_currentWordColorKey, 0xFFFFBF00);
    await prefs.setInt(_futureWordColorKey, 0xFF000000);
  }

  Future<void> applySessionStyles(Map<String, dynamic> styles) async {
    final hasScriptBgColor = styles.containsKey('scriptBgColor');
    final hasCurrentWordColor = styles.containsKey('currentWordColor');
    final hasFutureWordColor = styles.containsKey('futureWordColor');
    final hasLineSpacing = styles.containsKey('lineSpacing');
    final hasWordSpacing = styles.containsKey('wordSpacing');
    final hasLetterSpacing = styles.containsKey('letterSpacing');
    final hasFontSize = styles.containsKey('fontSize');
    final hasFontFamily = styles.containsKey('fontFamily');
    final hasTextAlign = styles.containsKey('textAlign');

    final scriptBgColor = hasScriptBgColor && styles['scriptBgColor'] is int
        ? _normalizeColor(styles['scriptBgColor'] as int, state.scriptBgColor)
        : state.scriptBgColor;
    final currentWordColor =
        hasCurrentWordColor && styles['currentWordColor'] is int
            ? _normalizeColor(
                styles['currentWordColor'] as int,
                state.currentWordColor,
              )
            : state.currentWordColor;
    final futureWordColor =
        hasFutureWordColor && styles['futureWordColor'] is int
            ? _normalizeColor(
                styles['futureWordColor'] as int,
                state.futureWordColor,
              )
            : state.futureWordColor;
    final lineSpacing = hasLineSpacing && styles['lineSpacing'] is num
        ? _normalizeLineSpacing((styles['lineSpacing'] as num).toDouble())
        : state.lineSpacing;
    final wordSpacing = hasWordSpacing && styles['wordSpacing'] is num
        ? _normalizeWordSpacing((styles['wordSpacing'] as num).toDouble())
        : state.wordSpacing;
    final letterSpacing = hasLetterSpacing && styles['letterSpacing'] is num
        ? _normalizeLetterSpacing((styles['letterSpacing'] as num).toDouble())
        : state.letterSpacing;
    final fontSize = hasFontSize && styles['fontSize'] is num
        ? (styles['fontSize'] as num).toDouble().clamp(14.0, 120.0).toDouble()
        : state.fontSize;
    final fontFamily = hasFontFamily && styles['fontFamily'] is String
        ? (styles['fontFamily'] as String).trim()
        : state.fontFamily;
    final textAlign = hasTextAlign && styles['textAlign'] is String
        ? _normalizeTextAlign(styles['textAlign'] as String)
        : state.textAlign;

    state = state.copyWith(
      scriptBgColor: scriptBgColor,
      currentWordColor: currentWordColor,
      futureWordColor: futureWordColor,
      lineSpacing: lineSpacing,
      wordSpacing: wordSpacing,
      letterSpacing: letterSpacing,
      fontSize: fontSize,
      fontFamily: fontFamily.isEmpty ? state.fontFamily : fontFamily,
      textAlign: textAlign,
    );
    final prefs = await SharedPreferences.getInstance();
    if (hasScriptBgColor) {
      await prefs.setInt(_scriptBgColorKey, scriptBgColor);
    }
    if (hasCurrentWordColor) {
      await prefs.setInt(_currentWordColorKey, currentWordColor);
    }
    if (hasFutureWordColor) {
      await prefs.setInt(_futureWordColorKey, futureWordColor);
    }
    if (hasLineSpacing) {
      await prefs.setDouble(_lineSpacingKey, lineSpacing);
    }
    if (hasWordSpacing) {
      await prefs.setDouble(_wordSpacingKey, wordSpacing);
    }
    if (hasLetterSpacing) {
      await prefs.setDouble(_letterSpacingKey, letterSpacing);
    }
    if (hasFontSize) {
      await prefs.setDouble(_fontSizeKey, fontSize);
    }
    if (hasFontFamily && fontFamily.isNotEmpty) {
      await prefs.setString(_fontFamilyKey, fontFamily);
    }
    if (hasTextAlign) {
      await prefs.setString(_textAlignKey, textAlign);
    }
  }

  Future<void> setFontFamily(String family) async {
    state = state.copyWith(fontFamily: family);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontFamilyKey, family);
  }

  Future<void> setLastImportPath(String path) async {
    state = state.copyWith(lastImportPath: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastImportPathKey, path);
  }

  void applyPreset(String type) {
    switch (type) {
      case 'Classic':
        state = state.copyWith(
          fontSize: 42,
          lineSpacing: 1.7,
          currentWordColor: 0xFFFFBF00,
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'High Contrast':
        state = state.copyWith(
          fontSize: 48,
          lineSpacing: 1.8,
          currentWordColor: 0xFF00FF00,
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'Modern Soft':
        state = state.copyWith(
          fontSize: 38,
          lineSpacing: 1.6,
          currentWordColor: 0xFF00BFFF,
          scriptBgColor: 0xFF121212,
          futureWordColor: 0xFFE0E0E0,
        );
        break;
    }
  }

  Future<void> setShowCurrentWordHighlight(bool val) async {
    state = state.copyWith(showCurrentWordHighlight: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showCurrentWordHighlightKey, val);
  }

  Future<void> setShowUpcomingWordColor(bool val) async {
    state = state.copyWith(showUpcomingWordColor: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showUpcomingWordColorKey, val);
  }

  Future<void> setShowAlignmentOverride(bool val) async {
    state = state.copyWith(showAlignmentOverride: val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showAlignmentOverrideKey, val);
  }
}
