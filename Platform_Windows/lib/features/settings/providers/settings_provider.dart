import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/security/secure_script_store.dart';
import '../models/app_settings.dart';

export '../models/app_settings.dart';

part 'settings_provider.keys.dart';
part 'settings_provider.secure_scripts.dart';
part 'settings_provider.appearance.dart';
part 'settings_provider.stt.dart';

class SettingsNotifier extends Notifier<AppSettings>
    with SettingsNotifierAppearance, SettingsNotifierSttSettings {
  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawRecents = prefs.getStringList(_recentScriptsKey) ?? [];

    final List<String> sanitizedRecents = [];
    bool needsResave = false;

    for (final json in rawRecents) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(json));
        bool itemModified = false;

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

        if (decoded['lastModified'] == null) {
          decoded['lastModified'] = DateTime.now().toIso8601String();
          itemModified = true;
        }
        if (decoded['date'] == null) {
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
      videoResolution: prefs.getString(_videoResolutionKey) ?? '720p',
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
    );
  }

  Future<void> saveScript(
    String text, {
    String? title,
    String? type,
    int? historyIndex,
    String? sessionId,
    bool isSilent = false,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    String? historyJson,
  }) async {
    final currentTitle = title ?? state.lastScriptTitle;
    final secureRecord = await _saveEncryptedScriptRecord(
      text: text,
      sessionId: sessionId,
      historyJson: historyJson,
    );
    final effectiveSessionId = secureRecord.sessionId;
    final secureRecordId = secureRecord.recordId;

    if (!isSilent) {
      state = state.copyWith(
        lastScript: '',
        lastScriptTitle: currentTitle,
        lastScriptSessionId: secureRecordId,
        lastHistoryIndex: historyIndex ?? state.lastHistoryIndex,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastScriptKey);
    await prefs.setString(_lastScriptSessionIdKey, secureRecordId);
    if (title != null) {
      await prefs.setString('last_script_title', title);
    }

    final recentList = List<String>.from(state.recentScripts);
    bool updated = false;

    for (int i = 0; i < recentList.length; i++) {
      try {
        final decoded = jsonDecode(recentList[i]);
        final itemSessionId = decoded['sessionId'];
        final itemTitle = decoded['title'];

        bool isMatch = false;
        if (sessionId != null && itemSessionId == sessionId) {
          isMatch = true;
        } else if (sessionId == null && itemTitle == currentTitle) {
          isMatch = true;
        }

        if (isMatch) {
          decoded['sessionId'] = effectiveSessionId;
          decoded[SecureScriptStore.recordIdKey] = secureRecordId;
          decoded[SecureScriptStore.storageVersionKey] =
              SecureScriptStore.storageVersion;
          decoded.remove('fullText');
          decoded.remove('historyJson');
          decoded.remove('snippet');
          if (historyIndex != null) decoded['historyIndex'] = historyIndex;
          if (type != null) decoded['type'] = type;
          if (decoded['type'] == null) decoded['type'] = 'FILE';

          final styleMap = decoded['style'] as Map<String, dynamic>? ?? {};
          if (fontSize != null) styleMap['fontSize'] = fontSize;
          if (fontFamily != null) styleMap['fontFamily'] = fontFamily;
          if (lineSpacing != null) styleMap['lineSpacing'] = lineSpacing;
          if (letterSpacing != null) styleMap['letterSpacing'] = letterSpacing;
          if (wordSpacing != null) styleMap['wordSpacing'] = wordSpacing;
          if (textAlign != null) styleMap['textAlign'] = textAlign;
          if (scriptBgColor != null) styleMap['scriptBgColor'] = scriptBgColor;
          if (currentWordColor != null) {
            styleMap['currentWordColor'] = currentWordColor;
          }
          if (futureWordColor != null) {
            styleMap['futureWordColor'] = futureWordColor;
          }

          if (styleMap.isNotEmpty) decoded['style'] = styleMap;

          recentList.removeAt(i);
          recentList.insert(0, jsonEncode(decoded));

          updated = true;
          break;
        }
      } catch (_) {}
    }

    if (updated) {
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    } else if (secureRecordId.isNotEmpty) {
      final newEntry = {
        'title': currentTitle,
        'type': type ?? 'FILE', // v3.9.5.54: Restore Label Integrity
        'sessionId': effectiveSessionId,
        SecureScriptStore.recordIdKey: secureRecordId,
        SecureScriptStore.storageVersionKey: SecureScriptStore.storageVersion,
        'historyIndex': historyIndex ?? 0,
        'lastModified': DateTime.now().toIso8601String(),
        'style': {
          if (fontSize != null) 'fontSize': fontSize,
          if (fontFamily != null) 'fontFamily': fontFamily,
          if (lineSpacing != null) 'lineSpacing': lineSpacing,
          if (letterSpacing != null) 'letterSpacing': letterSpacing,
          if (wordSpacing != null) 'wordSpacing': wordSpacing,
          if (textAlign != null) 'textAlign': textAlign,
          if (scriptBgColor != null) 'scriptBgColor': scriptBgColor,
          if (currentWordColor != null) 'currentWordColor': currentWordColor,
          if (futureWordColor != null) 'futureWordColor': futureWordColor,
        },
      };
      recentList.insert(0, jsonEncode(newEntry));
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    }

    if (historyIndex != null) {
      await prefs.setInt(_lastHistoryIndexKey, historyIndex);
    }
  }

  Future<void> addToRecent(String metadataJson) async {
    final list = List<String>.from(state.recentScripts);
    final newData = await _secureIncomingRecentMetadata(metadataJson);
    final String? newSessionId = newData['sessionId'] as String?;
    final String? newTitle = newData['title'] as String?;

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

    list.insert(0, jsonEncode(newData));
    if (list.length > 20) list.removeLast();

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
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

  Future<void> removeFromRecent(String sessionId) async {
    final list = List<String>.from(state.recentScripts);
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return decoded['sessionId'] == sessionId;
      } catch (e) {
        return false;
      }
    });

    state = state.copyWith(recentScripts: list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
