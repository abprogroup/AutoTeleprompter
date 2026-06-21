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

    if (!isSilent) {
      state = state.copyWith(
        lastScript: text,
        lastScriptTitle: currentTitle,
        lastHistoryIndex: historyIndex ?? state.lastHistoryIndex,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastScriptKey, text);
    if (title != null) {
      await prefs.setString('last_script_title', title);
    }

    final recentList = List<String>.from(state.recentScripts);
    var updated = false;

    for (var i = 0; i < recentList.length; i++) {
      try {
        final decoded = jsonDecode(recentList[i]);
        final itemSessionId = decoded['sessionId'];
        final itemTitle = decoded['title'];

        var isMatch = false;
        if (sessionId != null && itemSessionId == sessionId) {
          isMatch = true;
        } else if (sessionId == null && itemTitle == currentTitle) {
          isMatch = true;
        }

        if (isMatch) {
          decoded['fullText'] = text;
          if (historyIndex != null) decoded['historyIndex'] = historyIndex;
          if (type != null) decoded['type'] = type;
          if (decoded['type'] == null) decoded['type'] = 'FILE';
          if (sourcePath != null && sourcePath.trim().isNotEmpty) {
            decoded['sourcePath'] = sourcePath;
          }
          if (historyJson != null) decoded['historyJson'] = historyJson;

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
    } else if (sessionId != null) {
      final newEntry = {
        'title': currentTitle,
        'fullText': text,
        'type': type ?? 'FILE',
        if (sourcePath != null && sourcePath.trim().isNotEmpty)
          'sourcePath': sourcePath,
        'sessionId': sessionId,
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
        'historyJson': historyJson,
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
    final text = item['fullText']?.toString() ?? '';
    if (text.trim().isEmpty) return;
    try {
      await LocalBackupService().backupDeletedScript(
        title: item['title']?.toString() ?? 'Untitled script',
        text: text,
        sourceType: item['type']?.toString(),
        sourcePath: item['sourcePath']?.toString(),
        historyJson: item['historyJson']?.toString(),
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
