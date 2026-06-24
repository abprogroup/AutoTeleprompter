import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../../core/security/secure_script_store.dart';
import '../services/local_backup_service.dart';

part 'settings_provider.model.dart';
part 'settings_provider.keys.dart';
part 'settings_provider.script_persistence.dart';
part 'settings_provider.stt.dart';

class SettingsNotifier extends Notifier<AppSettings>
    with SettingsNotifierScriptPersistence, SettingsNotifierSttProfile {
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
        var decoded = Map<String, dynamic>.from(jsonDecode(json));
        bool itemModified = false;

        // 1. Repair Type Integrity (PDF/DOCX/RTF guessing)
        if (decoded['type'] == null || decoded['type'] == 'FILE') {
          final String title = (decoded['title'] ?? '').toLowerCase();
          String guessedType = 'FILE';
          if (title.endsWith('.pdf')) {
            guessedType = 'PDF';
          } else if (title.endsWith('.docx') || title.endsWith('.doc')) {
            guessedType = 'DOCX';
          } else if (title.endsWith('.rtf')) {
            guessedType = 'RTF';
          } else if (title.endsWith('.txt')) {
            guessedType = 'TXT';
          }

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
        final legacyText = decoded['fullText'];
        if (legacyText is String && legacyText.isNotEmpty) {
          decoded = await SecureScriptStore().secureMetadata(
            decoded,
            text: legacyText,
            historyJson: decoded['historyJson'] as String?,
          );
          itemModified = true;
        }

        if (itemModified) needsResave = true;
        sanitizedRecents.add(jsonEncode(decoded));
      } catch (_) {
        sanitizedRecents.add(json); // Preservation
      }
    }

    var recentsForState = sanitizedRecents;
    // Collapse any pre-existing duplicates (same file/title) accumulated before
    // the dedup guard existed, so the activity list shows each script once.
    if (_dedupeRecentMetadataList(recentsForState)) {
      needsResave = true;
    }
    if (needsResave) {
      await prefs.setStringList(_recentScriptsKey, recentsForState);
    }
    var lastScriptSessionId = prefs.getString(_lastScriptSessionIdKey) ?? '';
    final legacyLastScript = prefs.getString(_lastScriptKey) ?? '';
    if (legacyLastScript.trim().isNotEmpty) {
      try {
        final secureId = await SecureScriptStore().save(
          recordId: 'last_${DateTime.now().microsecondsSinceEpoch}',
          text: legacyLastScript,
        );
        lastScriptSessionId = secureId;
        await prefs.setString(_lastScriptSessionIdKey, secureId);
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.iosSecureLastScriptMigration',
        );
      }
      await prefs.remove(_lastScriptKey);
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
      fontSize: (prefs.getDouble(_fontSizeKey) ?? 20.0).clamp(10.0, 80.0),
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
      videoResolution: prefs.getString(_videoResolutionKey) ?? '720p',
      recentScripts: recentsForState,
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
      sttEngine: sanitizeSttEngine(prefs.getString(_sttEngineKey)),
      readFadeIntensity: prefs.getDouble(_readFadeIntensityKey) ?? 0.0,
      showSoundLevelMeter: prefs.getBool(_showSoundLevelMeterKey) ?? false,
      sttVisibleSkipEnabled: prefs.getBool(_sttVisibleSkipEnabledKey) ?? false,
      allowScrollDuringActiveSession:
          prefs.getBool(_allowScrollDuringActiveSessionKey) ?? false,
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
      sttInputDeviceId: prefs.getString(_sttInputDeviceIdKey) ?? '',
      sttInputDeviceLabel: prefs.getString(_sttInputDeviceLabelKey) ??
          'System default microphone',
      contentCreatorRecordingFormat: _normalizeContentCreatorRecordingFormat(
        prefs.getString(_contentCreatorRecordingFormatKey),
      ),
      contentCreatorRecordingAudioMode:
          _normalizeContentCreatorRecordingAudioMode(
        prefs.getString(_contentCreatorRecordingAudioModeKey),
      ),
      contentCreatorRecordingControlsSpeech:
          prefs.getBool(_contentCreatorRecordingControlsSpeechKey) ?? false,
      importColorMode: _normalizeImportColorMode(
        prefs.getString(_importColorModeKey),
      ),
      reduceMotion: prefs.getBool(_reduceMotionKey) ?? false,
      uiScale: _normalizeUiScale(prefs.getDouble(_uiScaleKey)),
      cloudAutoSyncOnSave: prefs.getBool(_cloudAutoSyncOnSaveKey) ?? true,
      syncDeletedScriptsFolder:
          prefs.getBool(_syncDeletedScriptsFolderKey) ?? false,
      recordingAutoBackup: prefs.getBool(_recordingAutoBackupKey) ?? false,
    );
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

  String _normalizeContentCreatorRecordingAudioMode(String? value) {
    switch (value) {
      case AppSettings.contentCreatorRecordingAudioCamera:
        return value!;
      default:
        return AppSettings.contentCreatorRecordingAudioCamera;
    }
  }

  String _normalizeImportColorMode(String? value) {
    switch (value) {
      case AppSettings.importColorModePrompter:
      case AppSettings.importColorModeDocument:
        return value!;
      default:
        return AppSettings.importColorModePrompter;
    }
  }

  double _normalizeUiScale(double? value) {
    return (value ?? 1.0).clamp(0.90, 1.25).toDouble();
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
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
    final clamped = spacing.clamp(0.5, 3.0).toDouble();
    state = state.copyWith(lineSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lineSpacingKey, clamped);
  }

  Future<void> setWordSpacing(double spacing) async {
    final clamped = spacing.clamp(-5.0, 20.0).toDouble();
    state = state.copyWith(wordSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wordSpacingKey, clamped);
  }

  Future<void> setLetterSpacing(double spacing) async {
    final clamped = spacing.clamp(-2.0, 5.0).toDouble();
    state = state.copyWith(letterSpacing: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_letterSpacingKey, clamped);
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

  Future<void> addToRecent(String metadataJson) async {
    final list = List<String>.from(state.recentScripts);
    var newData = Map<String, dynamic>.from(jsonDecode(metadataJson));
    final legacyText = newData['fullText'];
    if (legacyText is String && legacyText.isNotEmpty) {
      newData = await SecureScriptStore().secureMetadata(
        newData,
        text: legacyText,
        historyJson: newData['historyJson'] as String?,
      );
    }
    final String? newSessionId = newData['sessionId'] as String?;
    final String? newTitle = newData['title'] as String?;

    // Smart Upsert: Deduplicate by sessionId OR (fullText + title)
    // Smart Upsert: Deduplicate by title (Primary) or sessionId
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        final bool idMatch =
            newSessionId != null && decoded['sessionId'] == newSessionId;
        final bool titleMatch =
            newTitle != null && decoded['title'] == newTitle;
        return idMatch || titleMatch;
      } catch (e) {
        return false;
      }
    });

    // Insert the latest version at the top
    list.insert(0, jsonEncode(newData));
    if (list.length > 20) list.removeLast();

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
  }

  Future<void> removeFromRecent(String sessionId) async {
    final list = List<String>.from(state.recentScripts);
    final removedItems = <Map<String, dynamic>>[];
    list.removeWhere((item) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        final matches = decoded['sessionId'] == sessionId;
        if (matches) removedItems.add(decoded);
        return matches;
      } catch (e) {
        return false;
      }
    });

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
    for (final item in removedItems) {
      await _backupRemovedRecentItem(item);
      await SecureScriptStore().delete(
        SecureScriptStore.recordIdFromMetadata(item),
      );
    }
  }

  Future<void> setDisplayName(String name) async {
    state = state.copyWith(displayName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }

  Future<void> seedDisplayNameFromEmail(String email) async {
    final current = state.displayName.trim();
    if (current.isNotEmpty && current != 'Guest') return;
    final localPart = email.trim().split('@').first.trim();
    if (localPart.isEmpty) return;
    await setDisplayName(localPart);
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

  Future<void> setDocumentImportAppearance({int? scriptBgColor}) async {
    final normalizedBg = scriptBgColor ?? 0xFFFFFFFF;
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
    if (styles.containsKey('scriptBgColor')) {
      await prefs.setInt(_scriptBgColorKey, styles['scriptBgColor']);
    }
    if (styles.containsKey('currentWordColor')) {
      await prefs.setInt(_currentWordColorKey, styles['currentWordColor']);
    }
    if (styles.containsKey('futureWordColor')) {
      await prefs.setInt(_futureWordColorKey, styles['futureWordColor']);
    }
    if (styles.containsKey('lineSpacing')) {
      await prefs.setDouble(
          _lineSpacingKey, (styles['lineSpacing'] as num).toDouble());
    }
    if (styles.containsKey('wordSpacing')) {
      await prefs.setDouble(
          _wordSpacingKey, (styles['wordSpacing'] as num).toDouble());
    }
    if (styles.containsKey('letterSpacing')) {
      await prefs.setDouble(
          _letterSpacingKey, (styles['letterSpacing'] as num).toDouble());
    }
    if (styles.containsKey('fontSize')) {
      await prefs.setDouble(
          _fontSizeKey, (styles['fontSize'] as num).toDouble());
    }
    if (styles.containsKey('fontFamily')) {
      await prefs.setString(_fontFamilyKey, styles['fontFamily']);
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
