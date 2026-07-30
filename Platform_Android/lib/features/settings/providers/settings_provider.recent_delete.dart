part of 'settings_provider.dart';

mixin SettingsNotifierRecentDelete on Notifier<AppSettings> {
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

    // v3.9.8.1: Mandatory recentList sync to preserve Undo state
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
        final itemIdentityKeys = _recentIdentityKeys(
          title: itemTitle?.toString(),
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );

        bool isMatch = false;
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

          // v3.9.5.70: Persist detected/applied metadata (Nested for Gallery Compatibility)
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

          // v3.9.5.56: Positional Sovereignty (Lift-and-Prepend)
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
      }
    }

    if (updated) {
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    } else if (secureRecordId.isNotEmpty) {
      // v3.9.5.52: Automatic Prepention for new sessions
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
        // v3.9.5.70: Initial metadata baseline (Nested for Gallery Compatibility)
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
    if (!isSilent) {
      await _syncLocalBackupSnapshot(
        title: currentTitle,
        text: text,
        sourceType: type,
        sourcePath: sourcePath,
        sessionId: effectiveSessionId,
        historyJson: historyJson,
        fontSize: fontSize,
        fontFamily: fontFamily,
        textAlign: textAlign,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
      );
    }
    // NOTE: Windows also mirrors this snapshot to connected cloud providers
    // (Google Drive/Dropbox) here when `state.cloudAutoSyncOnSave` is set.
    // Android has no cloud feature yet (`android_parity_gaps.md` #5) - add
    // the same gated call once cloud sync lands, matching Windows exactly.
  }

  /// Writes a readable-format snapshot to the Local Backup folder (if the
  /// user has enabled it). Ported from Windows' `_syncSavedScriptSnapshot` -
  /// only the local-disk half, since Android has no cloud provider yet.
  Future<void> _syncLocalBackupSnapshot({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? sessionId,
    String? historyJson,
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
  }) async {
    if (text.trim().isEmpty) return;
    if (!await CloudConnectionStore().isLocalBackupEnabled()) return;
    var bookmarks = const <ScriptBookmark>[];
    try {
      bookmarks = await ScriptBookmarkService.load(
        ScriptBookmarkService.scopeKey(sessionId, title),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.localBackupBookmarks',
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

  Future<void> removeFromRecent(String sessionId) async {
    await deleteRecentScript(sessionId: sessionId);
  }

  /// Removes one recent script by [sessionId] or [title], deleting its
  /// encrypted record and backing it up to the local "Deleted Scripts"
  /// recovery folder (if Local Backup is enabled). Windows also mirrors the
  /// deletion to connected cloud providers here - Android has no cloud
  /// feature yet (`android_parity_gaps.md` #5). Add that hook once cloud
  /// sync lands, matching Windows exactly.
  Future<void> deleteRecentScript({
    String? sessionId,
    String? title,
  }) async {
    final list = List<String>.from(state.recentScripts);
    final removedRecordIds = <String>{};
    final removedItems = <Map<String, dynamic>>[];
    final targetIdentityKeys = <String>{};
    var removedActiveScript = false;

    for (final item in list) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        final itemSessionId = decoded['sessionId'] as String?;
        final itemRecordId = SecureScriptStore.recordIdFromMetadata(decoded);
        final itemTitle = decoded['title'] as String?;
        final matches = (sessionId != null && itemSessionId == sessionId) ||
            (sessionId != null && itemRecordId == sessionId) ||
            (title != null && itemTitle == title);
        if (!matches) continue;
        targetIdentityKeys.addAll(_recentIdentityKeys(
          title: itemTitle,
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        ));
      } catch (_) {
        continue;
      }
    }

    list.removeWhere((item) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        final itemSessionId = decoded['sessionId'] as String?;
        final itemRecordId = SecureScriptStore.recordIdFromMetadata(decoded);
        final itemTitle = decoded['title'] as String?;
        final itemIdentityKeys = _recentIdentityKeys(
          title: itemTitle,
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );
        final identityMatch = targetIdentityKeys.isNotEmpty &&
            itemIdentityKeys.any(targetIdentityKeys.contains);
        final matches = (sessionId != null && itemSessionId == sessionId) ||
            (sessionId != null && itemRecordId == sessionId) ||
            (title != null && itemTitle == title) ||
            identityMatch;
        if (!matches) return false;
        final recordId = itemRecordId;
        if (recordId != null) removedRecordIds.add(recordId);
        removedItems.add(decoded);
        removedActiveScript = removedActiveScript ||
            recordId == state.lastScriptSessionId ||
            itemSessionId == state.lastScriptSessionId;
        return true;
      } catch (e) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent metadata while removing script',
          data: {
            'source': 'removeFromRecent',
            'sessionId': sessionId ?? '',
            'title': title ?? '',
            'error': e.toString(),
          },
        );
        return false;
      }
    });

    _dedupeRecentMetadataList(list);
    state = state.copyWith(
      recentScripts: list,
      lastScript: removedActiveScript ? '' : state.lastScript,
      lastScriptSessionId: removedActiveScript ? '' : state.lastScriptSessionId,
      lastScriptTitle: removedActiveScript ? '' : state.lastScriptTitle,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
    if (removedActiveScript) {
      await Future.wait([
        prefs.remove(_lastScriptKey),
        prefs.remove(_lastScriptSessionIdKey),
        prefs.remove('last_script_title'),
      ]);
    }

    await _backupRemovedItemsToDeletedFolder(removedItems,
        fallbackTitle: title);

    final secureStore = SecureScriptStore();
    for (final recordId in removedRecordIds) {
      try {
        await secureStore.delete(recordId);
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.deleteSecureRecentScript',
          data: {'recordId': recordId},
        );
      }
    }
  }

  /// Batch version of [deleteRecentScript]. Same Local Backup / deferred
  /// cloud note applies.
  Future<void> deleteRecentScripts(
    List<Map<String, dynamic>> targets,
  ) async {
    if (targets.isEmpty) return;
    final targetSessionIds = <String>{};
    final targetRecordIds = <String>{};
    final targetTitles = <String>{};
    final targetIdentityKeys = <String>{};

    for (final target in targets) {
      final sessionId = target['sessionId']?.toString();
      if (sessionId != null && sessionId.isNotEmpty) {
        targetSessionIds.add(sessionId);
      }
      final recordId = SecureScriptStore.recordIdFromMetadata(target);
      if (recordId != null && recordId.isNotEmpty) {
        targetRecordIds.add(recordId);
      }
      final title = target['title']?.toString();
      if (title != null && title.isNotEmpty) targetTitles.add(title);
      targetIdentityKeys.addAll(_recentIdentityKeys(
        title: title,
        type: target['type']?.toString(),
        sourcePath: target['sourcePath']?.toString(),
      ));
    }

    final list = List<String>.from(state.recentScripts);
    final removedRecordIds = <String>{};
    final removedItems = <Map<String, dynamic>>[];
    var removedActiveScript = false;

    list.removeWhere((item) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(item));
        final itemSessionId = decoded['sessionId']?.toString();
        final itemRecordId = SecureScriptStore.recordIdFromMetadata(decoded);
        final itemTitle = decoded['title']?.toString();
        final itemIdentityKeys = _recentIdentityKeys(
          title: itemTitle,
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );
        final identityMatch = targetIdentityKeys.isNotEmpty &&
            itemIdentityKeys.any(targetIdentityKeys.contains);
        final matches = (itemSessionId != null &&
                targetSessionIds.contains(itemSessionId)) ||
            (itemRecordId != null && targetRecordIds.contains(itemRecordId)) ||
            (itemTitle != null && targetTitles.contains(itemTitle)) ||
            identityMatch;
        if (!matches) return false;
        if (itemRecordId != null) removedRecordIds.add(itemRecordId);
        removedItems.add(decoded);
        removedActiveScript = removedActiveScript ||
            itemRecordId == state.lastScriptSessionId ||
            itemSessionId == state.lastScriptSessionId;
        return true;
      } catch (e) {
        LightweightDiagnostics.instance.record(
          'settings',
          'ignored malformed recent metadata while batch removing scripts',
          data: {'source': 'removeRecentBatch', 'error': e.toString()},
        );
        return false;
      }
    });

    _dedupeRecentMetadataList(list);
    state = state.copyWith(
      recentScripts: list,
      lastScript: removedActiveScript ? '' : state.lastScript,
      lastScriptSessionId: removedActiveScript ? '' : state.lastScriptSessionId,
      lastScriptTitle: removedActiveScript ? '' : state.lastScriptTitle,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentScriptsKey, list);
    if (removedActiveScript) {
      await Future.wait([
        prefs.remove(_lastScriptKey),
        prefs.remove(_lastScriptSessionIdKey),
        prefs.remove('last_script_title'),
      ]);
    }

    await _backupRemovedItemsToDeletedFolder(removedItems);

    final secureStore = SecureScriptStore();
    await Future.wait(removedRecordIds.map((recordId) async {
      try {
        await secureStore.delete(recordId);
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.deleteSecureRecentScriptsBatch',
          data: {'recordId': recordId},
        );
      }
    }));
  }

  /// Backs up each removed recent-script entry to the local "Deleted
  /// Scripts" recovery folder (no-op if Local Backup is disabled), deduped
  /// by identity key so the same script isn't backed up twice in one batch.
  /// Ported from Windows' `deleteRecentScript`/`deleteRecentScripts`.
  Future<void> _backupRemovedItemsToDeletedFolder(
    List<Map<String, dynamic>> removedItems, {
    String? fallbackTitle,
  }) async {
    if (removedItems.isEmpty) return;
    if (!await CloudConnectionStore().isLocalBackupEnabled()) return;
    final secureStore = SecureScriptStore();
    final backedUpDeleteKeys = <String>{};
    for (final item in removedItems) {
      try {
        final itemKeys = _recentIdentityKeys(
          title: item['title']?.toString(),
          type: item['type']?.toString(),
          sourcePath: item['sourcePath']?.toString(),
        );
        final backupKey = itemKeys.isNotEmpty
            ? itemKeys.first
            : 'session:${item['sessionId']?.toString() ?? item.hashCode}';
        if (!backedUpDeleteKeys.add(backupKey)) continue;
        final data = await secureStore.readFromMetadata(item);
        final titleForDelete =
            item['title']?.toString() ?? fallbackTitle ?? 'Untitled script';
        final sourceType = item['type']?.toString();
        final sourcePath = item['sourcePath']?.toString();
        final textForDelete = data?.text ?? '';
        await LocalBackupService().backupDeletedScript(
          title: titleForDelete,
          text: textForDelete,
          sourceType: sourceType,
          sourcePath: sourcePath,
          historyJson: data?.historyJson,
          historyIndex: (item['historyIndex'] as num?)?.toInt(),
          recentMetadata: item,
        );
        DeletedScriptsService.notifyChanged();
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.backupDeletedScript',
          data: {
            'sessionId': item['sessionId']?.toString() ?? '',
            'title': item['title']?.toString() ?? '',
          },
        );
      }
    }
  }

  Future<DeletedScriptRestoreResult?> restoreDeletedScript(
    DeletedScriptEntry entry,
  ) async {
    final restored = await DeletedScriptsService().restoreLocalDeletedScript(
      entry,
    );
    if (restored == null) return null;
    await saveScript(
      restored.text,
      title: restored.title,
      type: restored.sourceType,
      sourcePath: restored.sourcePath,
      historyIndex: restored.historyIndex,
      historyJson: restored.historyJson,
      fontSize: restored.fontSize,
      fontFamily: restored.fontFamily,
      lineSpacing: restored.lineSpacing,
      letterSpacing: restored.letterSpacing,
      wordSpacing: restored.wordSpacing,
      textAlign: restored.textAlign,
      scriptBgColor: restored.scriptBgColor,
      currentWordColor: restored.currentWordColor,
      futureWordColor: restored.futureWordColor,
      isRtl: restored.isRtl,
    );
    DeletedScriptsService.notifyChanged();
    return restored;
  }

  Future<int> permanentlyDeleteDeletedScript(
    DeletedScriptEntry entry,
  ) async {
    return permanentlyDeleteDeletedScripts([entry]);
  }

  Future<int> permanentlyDeleteDeletedScripts(
    List<DeletedScriptEntry> entries,
  ) async {
    if (entries.isEmpty) return 0;
    final service = DeletedScriptsService();
    for (final entry in entries) {
      await service.permanentlyDeleteLocal(entry);
    }
    return 0;
  }

  Future<List<DeletedScriptEntry>> listDeletedScripts() {
    return DeletedScriptsService().listLocalDeletedScripts();
  }
}
