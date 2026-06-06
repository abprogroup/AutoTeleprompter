part of 'settings_provider.dart';

mixin SettingsNotifierRecentDelete on Notifier<AppSettings> {
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
            item['title']?.toString() ?? title ?? 'Untitled script';
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
        await _moveConnectedCloudScriptsToDeleted(
          title: titleForDelete,
          text: textForDelete,
          sourceType: sourceType,
          sourcePath: sourcePath,
        );
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
        final titleForDelete = item['title']?.toString() ?? 'Untitled script';
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
        await _moveConnectedCloudScriptsToDeleted(
          title: titleForDelete,
          text: textForDelete,
          sourceType: sourceType,
          sourcePath: sourcePath,
        );
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'settings.backupDeletedScriptsBatch',
          data: {
            'sessionId': item['sessionId']?.toString() ?? '',
            'title': item['title']?.toString() ?? '',
          },
        );
      }
    }

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

  Future<void> removeFromRecent(String sessionId) async {
    await deleteRecentScript(sessionId: sessionId);
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
    await _restoreConnectedCloudDeletedScripts(
      deletedFileName: entry.name,
      activeFileName: restored.cloudFileName,
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
    if (!state.syncDeletedScriptsFolder) return 0;
    return _permanentlyDeleteConnectedCloudDeletedScripts(entries);
  }

  Future<int> _permanentlyDeleteConnectedCloudDeletedScripts(
    List<DeletedScriptEntry> entries,
  ) async {
    var failures = 0;
    try {
      final accounts = await CloudOAuthService().loadAccounts();
      if (accounts.isEmpty) return failures;
      final sync = CloudAppFolderSyncService();
      final providerIds = accounts.keys.where((providerId) =>
          providerId == CloudConnectionStore.googleDrive ||
          providerId == CloudConnectionStore.dropbox);
      for (final providerId in providerIds) {
        for (final entry in entries) {
          try {
            final result = await sync.deleteDeletedScriptPermanently(
              providerId: providerId,
              deletedFileName: entry.name,
            );
            if (!result.ok) {
              failures++;
              LightweightDiagnostics.instance.record(
                'settings',
                'cloud deleted script permanent delete skipped',
                data: {
                  'providerId': providerId,
                  'deletedFileName': entry.name,
                  'message': result.message,
                },
              );
            }
          } catch (error, stack) {
            failures++;
            LightweightDiagnostics.instance.recordError(
              error,
              stack,
              source: 'settings.cloudDeletedScriptPermanentDelete',
              data: {
                'providerId': providerId,
                'deletedFileName': entry.name,
              },
            );
          }
        }
      }
    } catch (error, stack) {
      failures += entries.length;
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.cloudDeletedScriptPermanentDeleteAccounts',
      );
    }
    return failures;
  }

  Future<void> _moveConnectedCloudScriptsToDeleted({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
  }) async {
    if (text.trim().isEmpty) return;
    try {
      final accounts = await CloudOAuthService().loadAccounts();
      if (accounts.isEmpty) return;
      final sync = CloudAppFolderSyncService();
      for (final providerId in accounts.keys) {
        try {
          final result = await sync.moveScriptToDeleted(
            providerId: providerId,
            title: title,
            text: text,
            sourceType: sourceType,
            sourcePath: sourcePath,
          );
          if (!result.ok) {
            LightweightDiagnostics.instance.record(
              'settings',
              'cloud deleted script move skipped',
              data: {
                'providerId': providerId,
                'title': title,
                'message': result.message,
              },
            );
          }
        } catch (error, stack) {
          LightweightDiagnostics.instance.recordError(
            error,
            stack,
            source: 'settings.cloudDeletedScriptMove',
            data: {'providerId': providerId, 'title': title},
          );
        }
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.cloudDeletedScriptAccounts',
        data: {'title': title},
      );
    }
  }

  Future<void> _restoreConnectedCloudDeletedScripts({
    required String deletedFileName,
    required String activeFileName,
  }) async {
    try {
      final accounts = await CloudOAuthService().loadAccounts();
      if (accounts.isEmpty) return;
      final sync = CloudAppFolderSyncService();
      for (final providerId in accounts.keys) {
        try {
          final result = await sync.restoreDeletedScript(
            providerId: providerId,
            deletedFileName: deletedFileName,
            activeFileName: activeFileName,
          );
          if (!result.ok) {
            LightweightDiagnostics.instance.record(
              'settings',
              'cloud deleted script restore skipped',
              data: {
                'providerId': providerId,
                'deletedFileName': deletedFileName,
                'activeFileName': activeFileName,
                'message': result.message,
              },
            );
          }
        } catch (error, stack) {
          LightweightDiagnostics.instance.recordError(
            error,
            stack,
            source: 'settings.cloudDeletedScriptRestore',
            data: {
              'providerId': providerId,
              'deletedFileName': deletedFileName,
              'activeFileName': activeFileName,
            },
          );
        }
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.cloudDeletedScriptRestoreAccounts',
        data: {'deletedFileName': deletedFileName},
      );
    }
  }

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
  });
}

String _normalizeRecentPath(String? value) {
  final path = value?.trim();
  if (path == null || path.isEmpty) return '';
  return path.replaceAll('/', '\\').toLowerCase();
}

String _normalizeRecentTitle(String? value) {
  var title = value?.trim().toLowerCase() ?? '';
  var changed = true;
  while (changed) {
    changed = false;
    final next = title.replaceFirst(
      RegExp(r'\.(?:atp|atp\.txt)$', caseSensitive: false),
      '',
    );
    if (next != title) {
      title = next;
      changed = true;
    }
  }
  return title.replaceAll(RegExp(r'\s+'), ' ');
}

bool _dedupeRecentMetadataList(List<String> recentList) {
  final seen = <String>{};
  var changed = false;
  for (var i = 0; i < recentList.length; i++) {
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(recentList[i]));
      final keys = _recentIdentityKeys(
        title: decoded['title']?.toString(),
        type: decoded['type']?.toString(),
        sourcePath: decoded['sourcePath']?.toString(),
      );
      if (keys.isEmpty) continue;
      final duplicate = keys.any(seen.contains);
      if (!duplicate) {
        seen.addAll(keys);
        continue;
      }
      recentList.removeAt(i);
      changed = true;
      i--;
    } catch (_) {
      continue;
    }
  }
  return changed;
}

List<String> _recentIdentityKeys({
  String? title,
  String? type,
  String? sourcePath,
}) {
  final keys = <String>[];
  final path = _normalizeRecentPath(sourcePath);
  if (path.isNotEmpty) keys.add('path:$path');
  final cleanTitle = _normalizeRecentTitle(title);
  if (cleanTitle.isNotEmpty) {
    final cleanType = (type ?? '').trim().toUpperCase();
    keys.add('title:$cleanType:$cleanTitle');
  }
  return keys;
}
