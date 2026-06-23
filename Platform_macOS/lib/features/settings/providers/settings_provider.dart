import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/security/secure_script_store.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/script_project_codec.dart';
import '../models/app_settings.dart';
import '../services/cloud_app_folder_sync_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/deleted_scripts_service.dart';
import '../services/cloud_oauth_service.dart';
import '../services/local_backup_service.dart';

export '../models/app_settings.dart';

part 'settings_provider.keys.dart';
part 'settings_provider.normalizers.dart';
part 'settings_provider.secure_scripts.dart';
part 'settings_provider.appearance.dart';
part 'settings_provider.stt.dart';
part 'settings_provider.recent_delete.dart';

class SettingsNotifier extends Notifier<AppSettings>
    with
        SettingsNotifierAppearance,
        SettingsNotifierSttSettings,
        SettingsNotifierRecentDelete {
  int _loadGeneration = 0;
  bool _isDisposed = false;

  @override
  AppSettings build() {
    _isDisposed = false;
    final generation = ++_loadGeneration;
    ref.onDispose(() {
      _isDisposed = true;
      _loadGeneration++;
    });
    unawaited(_load(generation));
    return const AppSettings();
  }

  bool _canWriteLoadedState(int generation) {
    return !_isDisposed && generation == _loadGeneration;
  }

  Future<void> _load(int generation) async {
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
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent settings metadata',
          data: {
            'source': 'settingsLoad',
            'error': error.toString(),
          },
        );
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

    if (!_canWriteLoadedState(generation)) return;

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
      languageMode: _normalizeLanguageMode(prefs.getString(_languageKey)),
      scrollLead: _normalizeScrollLead(prefs.getDouble(_scrollLeadKey)),
      lastScript: '',
      lastScriptTitle: prefs.getString('last_script_title') ?? '',
      lastScriptSessionId: lastScriptSessionId,
      scrollMode: _normalizeScrollMode(prefs.getString(_scrollModeKey)),
      scrollSpeed: _normalizeScrollSpeed(prefs.getDouble(_scrollSpeedKey)),
      textAlign: _normalizeTextAlign(prefs.getString(_textAlignKey)),
      mirrorHorizontal: prefs.getBool(_mirrorHorizontalKey) ?? false,
      mirrorVertical: prefs.getBool(_mirrorVerticalKey) ?? false,
      flipRotation: _normalizeFlipRotation(prefs.getInt(_flipRotationKey)),
      lineSpacing: _normalizeLineSpacing(prefs.getDouble(_lineSpacingKey)),
      wordSpacing: _normalizeWordSpacing(prefs.getDouble(_wordSpacingKey)),
      letterSpacing:
          _normalizeLetterSpacing(prefs.getDouble(_letterSpacingKey)),
      scriptBgColor:
          _normalizeColor(prefs.getInt(_scriptBgColorKey), 0xFF000000),
      currentWordColor:
          _normalizeColor(prefs.getInt(_currentWordColorKey), 0xFFFFBF00),
      futureWordColor:
          _normalizeColor(prefs.getInt(_futureWordColorKey), 0xFFFFFFFF),
      pastWordOpacity:
          _normalizePastWordOpacity(prefs.getDouble(_pastWordOpacityKey)),
      debugMode: prefs.getBool(_debugModeKey) ?? false,
      showSoundLevelMeter: prefs.getBool(_showSoundLevelMeterKey) ?? false,
      videoResolution:
          _normalizeVideoResolution(prefs.getString(_videoResolutionKey)),
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
      sttEngine: _normalizeSttEngine(prefs.getString(_sttEngineKey)),
      allowScrollDuringActiveSession:
          prefs.getBool(_allowScrollDuringActiveSessionKey) ?? false,
      manualScrollBarPlacement: _normalizeManualScrollBarPlacement(
        prefs.getString(_manualScrollBarPlacementKey),
      ),
      readFadeIntensity: (prefs.getDouble(_readFadeIntensityKey) ?? 0.0)
          .clamp(0.0, 1.0)
          .toDouble(),
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
      defaultCameraDeviceName:
          prefs.getString(_defaultCameraDeviceNameKey) ?? '',
      contentCreatorCameraSourceMode: _normalizeContentCreatorCameraSource(
        prefs.getString(_contentCreatorCameraSourceModeKey),
      ),
      contentCreatorLayoutPreset: _normalizeContentCreatorLayout(
        prefs.getString(_contentCreatorLayoutPresetKey),
      ),
      contentCreatorCameraOpacity:
          (prefs.getDouble(_contentCreatorCameraOpacityKey) ?? 0.72)
              .clamp(0.2, 1.0)
              .toDouble(),
      contentCreatorFeedMode: _normalizeContentCreatorFeedMode(
        prefs.getString(_contentCreatorFeedModeKey),
      ),
      contentCreatorBubblePosition: _normalizeContentCreatorBubblePosition(
        prefs.getString(_contentCreatorBubblePositionKey),
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
      contentCreatorBubbleOffsetX:
          (prefs.getDouble(_contentCreatorBubbleOffsetXKey) ?? 0.0)
              .clamp(-0.25, 0.25)
              .toDouble(),
      contentCreatorBubbleOffsetY:
          (prefs.getDouble(_contentCreatorBubbleOffsetYKey) ?? 0.0)
              .clamp(-0.25, 0.25)
              .toDouble(),
      contentCreatorVignetteIntensity:
          (prefs.getDouble(_contentCreatorVignetteIntensityKey) ?? 0.45)
              .clamp(0.0, 1.0)
              .toDouble(),
      contentCreatorFeedBlur:
          (prefs.getDouble(_contentCreatorFeedBlurKey) ?? 14.0)
              .clamp(0.0, 30.0)
              .toDouble(),
      contentCreatorTextScrim:
          (prefs.getDouble(_contentCreatorTextScrimKey) ?? 0.55)
              .clamp(0.0, 0.9)
              .toDouble(),
      contentCreatorRecordingFolder: _normalizeLocalPath(
          prefs.getString(_contentCreatorRecordingFolderKey)),
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
      updateChannel: _normalizeUpdateChannel(
        prefs.getString(_updateChannelKey),
        allowInternal: true,
      ),
      checkUpdatesOnStartup: prefs.getBool(_checkUpdatesOnStartupKey) ?? true,
      cloudAutoSyncOnSave: prefs.getBool(_cloudAutoSyncOnSaveKey) ?? true,
      syncDeletedScriptsFolder:
          prefs.getBool(_syncDeletedScriptsFolderKey) ?? false,
      recordingAutoBackup: prefs.getBool(_recordingAutoBackupKey) ?? false,
      macOnboardingVersionSeen:
          prefs.getString(_macOnboardingVersionSeenKey) ?? '',
    );
  }

  @override
  Future<void> saveScript(
    String text, {
    String? title,
    String? type,
    String? sourcePath,
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
    bool? isRtl,
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
    final currentIdentityKeys = _recentIdentityKeys(
      title: currentTitle,
      type: type,
      sourcePath: sourcePath,
    );
    bool updated = false;

    for (int i = 0; i < recentList.length; i++) {
      try {
        final decoded = jsonDecode(recentList[i]);
        final itemSessionId = decoded['sessionId'];
        final itemTitle = decoded['title'];

        bool isMatch = false;
        final itemIdentityKeys = _recentIdentityKeys(
          title: itemTitle?.toString(),
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );

        if (sessionId != null && itemSessionId == sessionId) {
          isMatch = true;
        } else if (currentIdentityKeys.isNotEmpty &&
            itemIdentityKeys.any(currentIdentityKeys.contains)) {
          isMatch = true;
        } else if (sessionId == null && itemTitle == currentTitle) {
          isMatch = true;
        }

        if (isMatch) {
          decoded['title'] = currentTitle;
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
          if (sourcePath != null && sourcePath.trim().isNotEmpty) {
            decoded['sourcePath'] = sourcePath;
          }

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
          if (isRtl != null) styleMap['isRtl'] = isRtl;

          if (styleMap.isNotEmpty) decoded['style'] = styleMap;

          recentList.removeAt(i);
          recentList.insert(0, jsonEncode(decoded));
          _dedupeRecentMetadataList(recentList);

          updated = true;
          break;
        }
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent metadata during save',
          data: {
            'source': 'saveScriptRecentUpdate',
            'title': currentTitle,
            'error': error.toString(),
          },
        );
        try {
          final decoded = Map<String, dynamic>.from(jsonDecode(recentList[i]))
            ..remove('fullText')
            ..remove('historyJson')
            ..remove('snippet');
          recentList[i] = jsonEncode(decoded);
          updated = true;
        } catch (sanitizeError) {
          LightweightDiagnostics.instance.record(
            'settings',
            'failed to scrub malformed recent metadata during save',
            data: {
              'source': 'saveScriptRecentScrub',
              'title': currentTitle,
              'error': sanitizeError.toString(),
            },
          );
          recentList.removeAt(i);
          i--;
          updated = true;
        }
      }
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
        if (sourcePath != null && sourcePath.trim().isNotEmpty)
          'sourcePath': sourcePath,
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
          if (isRtl != null) 'isRtl': isRtl,
        },
      };
      recentList.insert(0, jsonEncode(newEntry));
      _dedupeRecentMetadataList(recentList);
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    }

    if (historyIndex != null) {
      await prefs.setInt(_lastHistoryIndexKey, historyIndex);
    }
    if (!isSilent && state.cloudAutoSyncOnSave) {
      await _syncSavedScriptSnapshot(
        title: currentTitle,
        text: text,
        sourceType: type,
        sourcePath: sourcePath,
        sessionId: effectiveSessionId,
        historyIndex: historyIndex,
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textAlign: textAlign,
        scriptBgColor: scriptBgColor,
        currentWordColor: currentWordColor,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
        historyJson: historyJson,
      );
    }
  }

  Future<void> _syncSavedScriptSnapshot({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? sessionId,
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
    bool? isRtl,
    String? historyJson,
  }) async {
    if (text.trim().isEmpty) return;
    var bookmarks = const <ScriptBookmark>[];
    try {
      bookmarks = await ScriptBookmarkService.load(
        ScriptBookmarkService.scopeKey(sessionId, title),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.projectBookmarks',
        data: {'title': title},
      );
    }

    try {
      await LocalBackupService().backupScript(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
        historyJson: historyJson,
        fontSize: fontSize,
        fontFamily: fontFamily,
        textAlign: textAlign,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
        bookmarks: bookmarks,
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.localBackupSnapshot',
        data: {'title': title},
      );
    }

    try {
      final oauth = CloudOAuthService();
      final accounts = await oauth.loadAccounts();
      final providerIds = accounts.keys
          .where((id) =>
              id == CloudConnectionStore.googleDrive ||
              id == CloudConnectionStore.dropbox)
          .toList(growable: false);
      if (providerIds.isEmpty) return;

      final readable = await LocalBackupService.buildScriptExportAsync(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
        fontSize: fontSize,
        fontFamily: fontFamily,
        textAlign: textAlign,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
        bookmarks: bookmarks,
      );
      LocalBackupService.validateExport(readable);
      if (readable.readableText.trim().isEmpty) return;

      final metadata = ScriptProjectCodec.buildCompanion(
        primaryFileName: readable.fileName,
        title: title,
        rawText: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
        sessionId: sessionId,
        historyJson: historyJson,
        historyIndex: historyIndex,
        fontSize: fontSize,
        fontFamily: fontFamily,
        lineSpacing: lineSpacing,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        textAlign: textAlign,
        scriptBgColor: scriptBgColor,
        currentWordColor: currentWordColor,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
        bookmarks: bookmarks,
      );
      final sync = CloudAppFolderSyncService(oauth: oauth);
      for (final providerId in providerIds) {
        final result = await sync.uploadScript(
          providerId: providerId,
          title: title,
          text: readable.readableText,
          fileName: readable.fileName,
          bytes: readable.bytes,
          mimeType: readable.mimeType,
          replaceExisting: true,
        );
        if (!result.ok) {
          LightweightDiagnostics.instance.record(
            'settings',
            'cloud autosync failed',
            data: {
              'title': title,
              'providerId': providerId,
              'message': result.message,
            },
          );
          continue;
        }

        final metadataResult = await sync.uploadScript(
          providerId: providerId,
          title: title,
          text: text,
          fileName: metadata.fileName,
          bytes: metadata.bytes,
          mimeType: metadata.mimeType,
          replaceExisting: true,
        );
        if (!metadataResult.ok) {
          LightweightDiagnostics.instance.record(
            'settings',
            'cloud autosync metadata failed',
            data: {
              'title': title,
              'providerId': providerId,
              'message': metadataResult.message,
            },
          );
          continue;
        }
        await sync.cleanupLegacyScriptArtifacts(
          providerId: providerId,
          primaryFileName: readable.fileName,
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.cloudAutoSyncSnapshot',
        data: {'title': title},
      );
    }
  }

  Future<void> addToRecent(String metadataJson) async {
    final list = List<String>.from(state.recentScripts);
    final newData = await _secureIncomingRecentMetadata(metadataJson);
    final String? newSessionId = newData['sessionId'] as String?;
    final String? newTitle = newData['title'] as String?;
    final List<String> newIdentityKeys = _recentIdentityKeys(
      title: newTitle,
      type: newData['type']?.toString(),
      sourcePath: newData['sourcePath']?.toString(),
    );

    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        final bool idMatch =
            newSessionId != null && decoded['sessionId'] == newSessionId;
        final bool titleMatch =
            newTitle != null && decoded['title'] == newTitle;
        final itemIdentityKeys = _recentIdentityKeys(
          title: decoded['title']?.toString(),
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );
        final identityMatch = newIdentityKeys.isNotEmpty &&
            itemIdentityKeys.any(newIdentityKeys.contains);
        return idMatch || identityMatch || titleMatch;
      } catch (error) {
        LightweightDiagnostics.instance.record(
          'settings',
          'removed malformed recent metadata while adding script',
          data: {
            'source': 'addToRecentDuplicateCheck',
            'title': newTitle,
            'error': error.toString(),
          },
        );
        return true;
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
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
