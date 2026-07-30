import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/security/secure_script_store.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/services/script_bookmark_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/deleted_scripts_service.dart';
import '../services/local_backup_service.dart';

part 'settings_provider.keys.dart';
part 'settings_provider.model.dart';
part 'settings_provider.recent_delete.dart';
part 'settings_provider.secure_scripts.dart';
part 'settings_provider.stt.dart';
part 'settings_provider.update.dart';

class SettingsNotifier extends Notifier<AppSettings>
    with
        SettingsNotifierRecentDelete,
        SettingsNotifierStt,
        SettingsNotifierUpdate {
  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawRecents = prefs.getStringList(_recentScriptsKey) ?? [];

    // v3.9.5.55: Institutional Heuristic Healer (Data Reconstruction)
    final List<String> sanitizedRecents = [];
    bool needsResave = false;

    for (final json in rawRecents) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(json));
        bool itemModified = false;

        // 1. Repair Type Integrity (PDF/DOCX/RTF guessing)
        if (decoded['type'] == null || decoded['type'] == 'FILE') {
          final String title = (decoded['title'] ?? '').toLowerCase();
          String guessedType = 'FILE';
          if (title.endsWith('.pdf'))
            guessedType = 'PDF';
          else if (title.endsWith('.docx') || title.endsWith('.doc'))
            guessedType = 'DOCX';
          else if (title.endsWith('.rtf'))
            guessedType = 'RTF';
          else if (title.endsWith('.txt')) guessedType = 'TXT';

          decoded['type'] = guessedType;
          itemModified = true;
        }

        // 2. Repair Date/Session IDs
        if (decoded['lastModified'] == null) {
          decoded['lastModified'] = DateTime.now().toIso8601String();
          itemModified = true;
        }
        if (decoded['date'] == null) {
          // Format date for UI compatibility (e.g. Apr 10, 2026)
          decoded['date'] = 'Imported Script';
          itemModified = true;
        }
        if (decoded['sessionId'] == null) {
          decoded['sessionId'] =
              'rec_${DateTime.now().millisecondsSinceEpoch}_${rawRecents.indexOf(json)}';
          itemModified = true;
        }

        if (itemModified) needsResave = true;
        sanitizedRecents.add(jsonEncode(decoded));
      } catch (_) {
        sanitizedRecents.add(json); // Preservation
      }
    }

    final secureMigration = await _migrateSecureScriptPreferences(
      prefs,
      sanitizedRecents,
    );
    final migratedRecents = secureMigration.recentScripts;
    if (_dedupeRecentMetadataList(migratedRecents)) {
      needsResave = true;
    }
    if (secureMigration.needsResave) {
      needsResave = true;
    }
    final lastScriptSessionId = secureMigration.lastScriptSessionId;

    if (needsResave) {
      await prefs.setStringList(_recentScriptsKey, migratedRecents);
    }

    final manualStartSmall =
        (prefs.getInt(_sttManualStartAdvanceSmallWordsKey) ?? 4)
            .clamp(2, 8)
            .toInt();
    final manualStartBig = (prefs.getInt(_sttManualStartAdvanceBigWordsKey) ??
            (manualStartSmall <= 2 ? 1 : manualStartSmall - 1))
        .clamp(1, 8)
        .toInt();
    final manualSafetySmall =
        (prefs.getInt(_sttManualSafetySmallWordsKey) ?? 2).clamp(1, 5).toInt();
    final manualSafetyBig = (prefs.getInt(_sttManualSafetyBigWordsKey) ??
            (manualSafetySmall <= 2 ? 1 : manualSafetySmall - 1))
        .clamp(1, 5)
        .toInt();
    final manualVisibleSmall =
        (prefs.getInt(_sttManualVisibleSkipSmallWordsKey) ?? 0)
            .clamp(0, 8)
            .toInt();
    final manualVisibleBig = (prefs.getInt(_sttManualVisibleSkipBigWordsKey) ??
            (manualVisibleSmall <= 0
                ? 0
                : (manualVisibleSmall <= 2 ? 1 : manualVisibleSmall - 1)))
        .clamp(0, 8)
        .toInt();
    final manualBigWordMinLetters =
        (prefs.getInt(_sttManualBigWordMinLettersKey) ?? 5)
            .clamp(3, 10)
            .toInt();

    state = AppSettings(
      settingsLoaded: true,
      fontSize:
          (prefs.getDouble(_fontSizeKey) ?? 20.0).clamp(14.0, 120.0).toDouble(),
      languageMode: prefs.getString(_languageKey) ?? 'auto',
      scrollLead: prefs.getDouble(_scrollLeadKey) ?? 0.32,
      lastScript: '',
      lastScriptTitle: prefs.getString('last_script_title') ?? '',
      lastScriptSessionId: lastScriptSessionId,
      scrollMode: prefs.getString(_scrollModeKey) ?? 'auto',
      scrollSpeed: prefs.getDouble(_scrollSpeedKey) ?? 100.0,
      textAlign: prefs.getString(_textAlignKey) ?? 'center',
      mirrorHorizontal: prefs.getBool(_mirrorHorizontalKey) ?? false,
      mirrorVertical: prefs.getBool(_mirrorVerticalKey) ?? false,
      flipRotation: prefs.getInt(_flipRotationKey) ?? 0,
      lineSpacing: prefs.getDouble(_lineSpacingKey) ?? 1.2,
      wordSpacing: prefs.getDouble(_wordSpacingKey) ?? 0.0,
      letterSpacing: prefs.getDouble(_letterSpacingKey) ?? 0.0,
      scriptBgColor: prefs.getInt(_scriptBgColorKey) ?? 0xFF000000,
      currentWordColor: prefs.getInt(_currentWordColorKey) ?? 0xFFFFBF00,
      futureWordColor: prefs.getInt(_futureWordColorKey) ?? 0xFFFFFFFF,
      pastWordOpacity: prefs.getDouble(_pastWordOpacityKey) ?? 0.3,
      debugMode: prefs.getBool(_debugModeKey) ?? false,
      showSoundLevelMeter: prefs.getBool(_showSoundLevelMeterKey) ?? false,
      videoResolution: prefs.getString(_videoResolutionKey) ?? '720p',
      contentCreatorRecordingControlsSpeech:
          prefs.getBool(_contentCreatorRecordingControlsSpeechKey) ?? false,
      contentCreatorRecordingFormat: _normalizeContentCreatorRecordingFormat(
        prefs.getString(_contentCreatorRecordingFormatKey),
      ),
      contentCreatorFeedMode: _normalizeContentCreatorFeedMode(
        prefs.getString(_contentCreatorFeedModeKey),
      ),
      contentCreatorBubbleShape: _normalizeContentCreatorBubbleShape(
        prefs.getString(_contentCreatorBubbleShapeKey),
      ),
      contentCreatorBubbleSize:
          (prefs.getDouble(_contentCreatorBubbleSizeKey) ?? 0.24)
              .clamp(0.04, 0.60)
              .toDouble(),
      contentCreatorBubbleOpacity:
          (prefs.getDouble(_contentCreatorBubbleOpacityKey) ?? 1.0)
              .clamp(0.25, 1.0)
              .toDouble(),
      contentCreatorBubbleRoundness:
          (prefs.getDouble(_contentCreatorBubbleRoundnessKey) ?? 0.18)
              .clamp(0.0, 1.0)
              .toDouble(),
      contentCreatorCameraOpacity:
          (prefs.getDouble(_contentCreatorCameraOpacityKey) ?? 0.72)
              .clamp(0.2, 1.0)
              .toDouble(),
      contentCreatorFeedBlur:
          (prefs.getDouble(_contentCreatorFeedBlurKey) ?? 14.0)
              .clamp(0.0, 30.0)
              .toDouble(),
      contentCreatorTextScrim:
          (prefs.getDouble(_contentCreatorTextScrimKey) ?? 0.55)
              .clamp(0.0, 0.9)
              .toDouble(),
      contentCreatorVignetteIntensity:
          (prefs.getDouble(_contentCreatorVignetteIntensityKey) ?? 0.45)
              .clamp(0.0, 1.0)
              .toDouble(),
      androidOnboardingVersionSeen:
          prefs.getString(_androidOnboardingVersionSeenKey) ?? '',
      androidPresenterOnboardingVersionSeen:
          prefs.getString(_androidPresenterOnboardingVersionSeenKey) ?? '',
      contentCreatorWalkthroughVersionSeen:
          prefs.getString(_contentCreatorWalkthroughVersionSeenKey) ?? '',
      recentScripts: migratedRecents,
      displayName: prefs.getString(_displayNameKey) ?? 'Guest',
      lastTextColor: prefs.getInt(_lastTextColorKey) ?? 0xFFFFBF00,
      lastHighlightColor: prefs.getInt(_lastHighlightColorKey) ?? 0x4DFFFFFF,
      lastImportPath: prefs.getString(_lastImportPathKey) ?? '',
      lastHistoryIndex: prefs.getInt(_lastHistoryIndexKey) ?? -1,
      showCurrentWordHighlight:
          prefs.getBool(_showCurrentWordHighlightKey) ?? true,
      showUpcomingWordColor: prefs.getBool(_showUpcomingWordColorKey) ?? false,
      fontFamily: prefs.getString(_fontFamilyKey) ?? 'Inter',
      showAlignmentOverride: prefs.getBool(_showAlignmentOverrideKey) ?? false,
      sttEngine: prefs.getString(_sttEngineKey) ?? 'google',
      readFadeIntensity: prefs.getDouble(_readFadeIntensityKey) ?? 0.0,
      sttInputDeviceId: prefs.getString(_sttInputDeviceIdKey) ?? '',
      sttInputDeviceLabel: prefs.getString(_sttInputDeviceLabelKey) ??
          'System default microphone',
      sttVisibleSkipEnabled: prefs.getBool(_sttVisibleSkipEnabledKey) ?? false,
      sttStrictBulletMode: prefs.getBool(_sttStrictBulletModeKey) ?? false,
      sttHardVisibleSkipEnabled:
          prefs.getBool(_sttHardVisibleSkipEnabledKey) ?? false,
      sttManualProfileEnabled:
          prefs.getBool(_sttManualProfileEnabledKey) ?? false,
      sttManualStartAdvanceSmallWords: manualStartSmall,
      sttManualStartAdvanceBigWords: manualStartBig,
      sttManualSafetySmallWords: manualSafetySmall,
      sttManualSafetyBigWords: manualSafetyBig,
      sttManualVisibleSkipSmallWords: manualVisibleSmall,
      sttManualVisibleSkipBigWords: manualVisibleBig,
      sttManualBigWordMinLetters: manualBigWordMinLetters,
      sttReliabilityMode:
          _normalizeSttReliabilityMode(prefs.getString(_sttReliabilityModeKey)),
      updateChannel:
          prefs.getString(_updateChannelKey) ?? AppSettings.updateChannelStable,
      checkUpdatesOnStartup: prefs.getBool(_checkUpdatesOnStartupKey) ?? false,
    );
  }

  Future<void> activateRecentScript(Map<String, dynamic> metadata) async {
    final activation = _prepareRecentActivation(metadata, state);
    state = activation.settings;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_lastScriptKey),
      prefs.setString(_lastScriptSessionIdKey, activation.recordId),
      prefs.setString('last_script_title', activation.title),
    ]);
    if (activation.historyIndex != null) {
      await prefs.setInt(_lastHistoryIndexKey, activation.historyIndex!);
    }
    if (activation.recentsChanged) {
      await prefs.setStringList(_recentScriptsKey, activation.recentScripts);
    }
  }

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(14.0, 120.0).toDouble();
    state = state.copyWith(fontSize: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, clamped);
  }

  Future<void> setLanguageMode(String mode) async {
    state = state.copyWith(languageMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, mode);
  }

  Future<void> setScrollLead(double lead) async {
    state = state.copyWith(scrollLead: lead);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollLeadKey, lead);
  }

  Future<void> setScrollMode(String mode) async {
    state = state.copyWith(scrollMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scrollModeKey, mode);
  }

  Future<void> setScrollSpeed(double speed) async {
    state = state.copyWith(scrollSpeed: speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scrollSpeedKey, speed);
  }

  Future<void> setTextAlign(String align) async {
    state = state.copyWith(textAlign: align);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textAlignKey, align);
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
    state = state.copyWith(flipRotation: degrees);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_flipRotationKey, degrees);
  }

  Future<void> setLineSpacing(double spacing) async {
    // v3.9.5.69: Allow ultra-tight spacing but clamp at 0.1 to avoid layout crashes
    final clamped = spacing < 0.1 ? 0.1 : spacing;
    state = state.copyWith(lineSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineSpacingKey, clamped);
  }

  Future<void> setWordSpacing(double spacing) async {
    state = state.copyWith(wordSpacing: spacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wordSpacingKey, spacing);
  }

  Future<void> setLetterSpacing(double spacing) async {
    state = state.copyWith(letterSpacing: spacing);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_letterSpacingKey, spacing);
  }

  Future<void> setScriptBgColor(int color) async {
    state = state.copyWith(scriptBgColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_scriptBgColorKey, color);
  }

  Future<void> setCurrentWordColor(int color) async {
    state = state.copyWith(currentWordColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentWordColorKey, color);
  }

  Future<void> setFutureWordColor(int color) async {
    state = state.copyWith(futureWordColor: color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_futureWordColorKey, color);
  }

  Future<void> setPastWordOpacity(double opacity) async {
    state = state.copyWith(pastWordOpacity: opacity);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pastWordOpacityKey, opacity);
  }

  Future<void> toggleDebugMode() async {
    final newVal = !state.debugMode;
    state = state.copyWith(debugMode: newVal);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModeKey, newVal);
  }

  Future<void> setVideoResolution(String resolution) async {
    state = state.copyWith(videoResolution: resolution);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoResolutionKey, resolution);
  }

  Future<void> setContentCreatorRecordingControlsSpeech(bool enabled) async {
    state = state.copyWith(contentCreatorRecordingControlsSpeech: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contentCreatorRecordingControlsSpeechKey, enabled);
  }

  Future<void> setContentCreatorRecordingFormat(String format) async {
    final normalized = switch (format) {
      AppSettings.contentCreatorRecordingFormatAudio =>
        AppSettings.contentCreatorRecordingFormatAudio,
      _ => AppSettings.contentCreatorRecordingFormatMp4,
    };
    state = state.copyWith(contentCreatorRecordingFormat: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorRecordingFormatKey, normalized);
  }

  String _normalizeContentCreatorRecordingFormat(String? value) {
    switch (value) {
      case AppSettings.contentCreatorRecordingFormatMp4:
      case AppSettings.contentCreatorRecordingFormatAudio:
        return value!;
      default:
        return AppSettings.contentCreatorRecordingFormatMp4;
    }
  }

  Future<void> setContentCreatorFeedMode(String mode) async {
    const allowed = {
      AppSettings.contentCreatorFeedStrip,
      AppSettings.contentCreatorFeedBubble,
      AppSettings.contentCreatorFeedFull,
    };
    final normalized =
        allowed.contains(mode) ? mode : AppSettings.contentCreatorFeedStrip;
    state = state.copyWith(contentCreatorFeedMode: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorFeedModeKey, normalized);
  }

  Future<void> setContentCreatorBubbleShape(String shape) async {
    const allowed = {
      AppSettings.contentCreatorBubbleRectangle,
      AppSettings.contentCreatorBubbleRounded,
      AppSettings.contentCreatorBubbleCircle,
    };
    final normalized = allowed.contains(shape)
        ? shape
        : AppSettings.contentCreatorBubbleRounded;
    state = state.copyWith(contentCreatorBubbleShape: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorBubbleShapeKey, normalized);
  }

  Future<void> _setContentCreatorDouble(
    String key,
    double value,
    double min,
    double max,
    AppSettings Function(double) apply,
  ) async {
    final clamped = value.clamp(min, max).toDouble();
    state = apply(clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, clamped);
  }

  Future<void> setContentCreatorBubbleSize(double value) =>
      _setContentCreatorDouble(_contentCreatorBubbleSizeKey, value, 0.04, 0.60,
          (v) => state.copyWith(contentCreatorBubbleSize: v));

  Future<void> setContentCreatorBubbleOpacity(double value) =>
      _setContentCreatorDouble(_contentCreatorBubbleOpacityKey, value, 0.25,
          1.0, (v) => state.copyWith(contentCreatorBubbleOpacity: v));

  Future<void> setContentCreatorBubbleRoundness(double value) =>
      _setContentCreatorDouble(_contentCreatorBubbleRoundnessKey, value, 0.0,
          1.0, (v) => state.copyWith(contentCreatorBubbleRoundness: v));

  Future<void> setContentCreatorCameraOpacity(double value) =>
      _setContentCreatorDouble(_contentCreatorCameraOpacityKey, value, 0.2, 1.0,
          (v) => state.copyWith(contentCreatorCameraOpacity: v));

  Future<void> setContentCreatorFeedBlur(double value) =>
      _setContentCreatorDouble(_contentCreatorFeedBlurKey, value, 0.0, 30.0,
          (v) => state.copyWith(contentCreatorFeedBlur: v));

  Future<void> setContentCreatorTextScrim(double value) =>
      _setContentCreatorDouble(_contentCreatorTextScrimKey, value, 0.0, 0.9,
          (v) => state.copyWith(contentCreatorTextScrim: v));

  Future<void> setContentCreatorVignetteIntensity(double value) =>
      _setContentCreatorDouble(_contentCreatorVignetteIntensityKey, value, 0.0,
          1.0, (v) => state.copyWith(contentCreatorVignetteIntensity: v));

  String _normalizeContentCreatorFeedMode(String? value) {
    switch (value) {
      case AppSettings.contentCreatorFeedStrip:
      case AppSettings.contentCreatorFeedBubble:
      case AppSettings.contentCreatorFeedFull:
        return value!;
      default:
        return AppSettings.contentCreatorFeedStrip;
    }
  }

  String _normalizeContentCreatorBubbleShape(String? value) {
    switch (value) {
      case AppSettings.contentCreatorBubbleRectangle:
      case AppSettings.contentCreatorBubbleRounded:
      case AppSettings.contentCreatorBubbleCircle:
        return value!;
      default:
        return AppSettings.contentCreatorBubbleRounded;
    }
  }

  Future<void> setAndroidOnboardingVersionSeen(String version) async {
    state = state.copyWith(androidOnboardingVersionSeen: version);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_androidOnboardingVersionSeenKey, version);
  }

  Future<void> setAndroidPresenterOnboardingVersionSeen(String version) async {
    state = state.copyWith(androidPresenterOnboardingVersionSeen: version);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_androidPresenterOnboardingVersionSeenKey, version);
  }

  Future<void> setContentCreatorWalkthroughVersionSeen(String version) async {
    state = state.copyWith(contentCreatorWalkthroughVersionSeen: version);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_contentCreatorWalkthroughVersionSeenKey, version);
  }

  Future<void> setDisplayName(String name) async {
    state = state.copyWith(displayName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
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
    // v3.9.5.60: Calibrated defaults — line spacing 1.2 matches AppSettings baseline
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

  Future<void> applySessionStyles(Map<String, dynamic> styles) async {
    // Apply saved styles from a specific session
    state = state.copyWith(
      scriptBgColor: styles['scriptBgColor'] ?? state.scriptBgColor,
      currentWordColor: styles['currentWordColor'] ?? state.currentWordColor,
      futureWordColor: styles['futureWordColor'] ?? state.futureWordColor,
      lineSpacing:
          (styles['lineSpacing'] as num?)?.toDouble() ?? state.lineSpacing,
      wordSpacing:
          (styles['wordSpacing'] as num?)?.toDouble() ?? state.wordSpacing,
      letterSpacing:
          (styles['letterSpacing'] as num?)?.toDouble() ?? state.letterSpacing,
      fontSize: (styles['fontSize'] as num?)?.toDouble() ?? state.fontSize,
      fontFamily: styles['fontFamily'] ?? state.fontFamily,
    );
    final prefs = await SharedPreferences.getInstance();
    if (styles.containsKey('scriptBgColor'))
      await prefs.setInt(_scriptBgColorKey, styles['scriptBgColor']);
    if (styles.containsKey('currentWordColor'))
      await prefs.setInt(_currentWordColorKey, styles['currentWordColor']);
    if (styles.containsKey('futureWordColor'))
      await prefs.setInt(_futureWordColorKey, styles['futureWordColor']);
    if (styles.containsKey('lineSpacing'))
      await prefs.setDouble(
          _lineSpacingKey, (styles['lineSpacing'] as num).toDouble());
    if (styles.containsKey('wordSpacing'))
      await prefs.setDouble(
          _wordSpacingKey, (styles['wordSpacing'] as num).toDouble());
    if (styles.containsKey('letterSpacing'))
      await prefs.setDouble(
          _letterSpacingKey, (styles['letterSpacing'] as num).toDouble());
    if (styles.containsKey('fontSize'))
      await prefs.setDouble(
          _fontSizeKey, (styles['fontSize'] as num).toDouble());
    if (styles.containsKey('fontFamily'))
      await prefs.setString(_fontFamilyKey, styles['fontFamily']);
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
          currentWordColor: 0xFFFFBF00, // Amber
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'High Contrast':
        state = state.copyWith(
          fontSize: 48,
          lineSpacing: 1.8,
          currentWordColor: 0xFF00FF00, // Green
          scriptBgColor: 0xFF000000,
          futureWordColor: 0xFFFFFFFF,
        );
        break;
      case 'Modern Soft':
        state = state.copyWith(
          fontSize: 38,
          lineSpacing: 1.6,
          currentWordColor: 0xFF00BFFF, // DeepSkyBlue
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

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
