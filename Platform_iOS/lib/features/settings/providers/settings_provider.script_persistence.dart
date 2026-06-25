part of 'settings_provider.dart';

mixin SettingsNotifierScriptPersistence on Notifier<AppSettings> {
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
    final effectiveSessionId =
        sessionId ?? 'script_${DateTime.now().microsecondsSinceEpoch}';
    final secureRecordId = text.trim().isEmpty
        ? ''
        : await SecureScriptStore().save(
            recordId: effectiveSessionId,
            text: text,
            historyJson: historyJson,
          );

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
    if (secureRecordId.isNotEmpty) {
      await prefs.setString(_lastScriptSessionIdKey, secureRecordId);
    }
    if (title != null) {
      await prefs.setString('last_script_title', title);
    }

    final recentList = List<String>.from(state.recentScripts);
    final currentIdentityKeys = _recentIdentityKeys(
      title: currentTitle,
      type: type,
      sourcePath: sourcePath,
    );
    var updated = false;

    for (var i = 0; i < recentList.length; i++) {
      try {
        final decoded = jsonDecode(recentList[i]);
        final itemSessionId = decoded['sessionId'];
        final itemTitle = decoded['title'];
        final itemIdentityKeys = _recentIdentityKeys(
          title: itemTitle?.toString(),
          type: decoded['type']?.toString(),
          sourcePath: decoded['sourcePath']?.toString(),
        );

        var isMatch = false;
        if (sessionId != null && itemSessionId == sessionId) {
          isMatch = true;
        } else if (currentIdentityKeys.isNotEmpty &&
            itemIdentityKeys.any(currentIdentityKeys.contains)) {
          isMatch = true;
        } else if (sessionId == null && itemTitle == currentTitle) {
          isMatch = true;
        }

        if (isMatch) {
          decoded['sessionId'] = effectiveSessionId;
          if (secureRecordId.isNotEmpty) {
            decoded[SecureScriptStore.recordIdKey] = secureRecordId;
            decoded[SecureScriptStore.storageVersionKey] =
                SecureScriptStore.storageVersion;
          }
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
        'type': type ?? 'FILE',
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
      if (!isSilent) {
        state = state.copyWith(recentScripts: recentList);
      }
      await prefs.setStringList(_recentScriptsKey, recentList);
    }

    if (historyIndex != null) {
      await prefs.setInt(_lastHistoryIndexKey, historyIndex);
    }
    if (!isSilent) {
      await _snapshotLocalBackup(
        title: currentTitle,
        text: text,
        sourceType: type,
        sourcePath: sourcePath,
        sessionId: sessionId,
        fontSize: fontSize,
        fontFamily: fontFamily,
        textAlign: textAlign,
        futureWordColor: futureWordColor,
        isRtl: isRtl,
        historyJson: historyJson,
      );
    }
  }

  Future<void> _snapshotLocalBackup({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? sessionId,
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    String? historyJson,
  }) async {
    if (text.trim().isEmpty) return;
    try {
      final bookmarks = await ScriptBookmarkService.load(
        ScriptBookmarkService.scopeKey(sessionId, title),
      );
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
      );
    }
  }

  Future<void> _backupRemovedRecentItem(Map<String, dynamic> item) async {
    try {
      final data = await SecureScriptStore().readFromMetadata(item);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) return;
      await LocalBackupService().backupDeletedScript(
        title: item['title']?.toString() ?? 'Untitled script',
        text: text,
        sourceType: item['type']?.toString(),
        sourcePath: item['sourcePath']?.toString(),
        historyJson: data?.historyJson,
        historyIndex: (item['historyIndex'] as num?)?.toInt(),
        recentMetadata: item,
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.localBackupDeletedScript',
      );
    }
  }
}

/// Collapses recent entries that point at the same script (same source file or
/// same normalized title+type) so the activity list never shows the same file
/// twice. Mirrors the macOS dedup so re-imports and re-saves coalesce. Returns
/// true if anything was removed.
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
    var cleanType = (type ?? '').trim().toUpperCase();
    // The walkthrough sample is first stored as WALKTHROUGH_SAMPLE on load, then
    // re-saved as a normal FILE from the editor. Treat them as the same script
    // so the activity list shows it once instead of twice.
    if (cleanType.isEmpty || cleanType == 'WALKTHROUGH_SAMPLE') {
      cleanType = 'FILE';
    }
    keys.add('title:$cleanType:$cleanTitle');
  }
  return keys;
}

String _normalizeRecentPath(String? value) {
  final path = value?.trim();
  if (path == null || path.isEmpty) return '';
  return path.replaceAll('\\', '/').toLowerCase();
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
