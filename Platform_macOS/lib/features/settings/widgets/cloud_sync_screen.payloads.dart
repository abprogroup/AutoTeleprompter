part of 'cloud_sync_screen.dart';

extension _CloudSyncScreenPayloads on _CloudSyncScreenState {
  Future<List<_CloudScriptPayload>> _scriptPayloadsForSync() async {
    final scripts = <_CloudScriptPayload>[];
    final seen = <String>{};
    final recentItems = ref.read(settingsProvider).recentScripts;
    final active = ref.read(scriptProvider);
    if (active != null &&
        active.rawText.trim().isNotEmpty &&
        _activeScriptStillInRecentActivity(active, recentItems)) {
      _addPayload(
        scripts,
        seen,
        _CloudScriptPayload(
          title: active.title,
          text: active.rawText,
          sourcePath: active.sourcePath,
          sourceType: active.sourceType,
          sessionId: active.sessionId,
          historyJson: active.historyJson,
          historyIndex: active.historyIndex,
          fontSize: active.fontSize,
          fontFamily: active.fontFamily,
          lineSpacing: active.lineSpacing,
          letterSpacing: active.letterSpacing,
          wordSpacing: active.wordSpacing,
          textAlign: active.textAlign,
          scriptBgColor: active.scriptBgColor,
          currentWordColor: active.currentWordColor,
          futureWordColor: active.futureWordColor,
          isRtl: active.isRtl,
          bookmarks: await _loadProjectBookmarks(
            sessionId: active.sessionId,
            title: active.title,
          ),
          identity: active.sessionId,
        ),
      );
    }

    final secureStore = SecureScriptStore();
    for (final item in recentItems) {
      try {
        final meta = Map<String, dynamic>.from(jsonDecode(item));
        final data = await secureStore.readFromMetadata(meta);
        final text = data?.text ?? '';
        if (text.trim().isEmpty) continue;
        final title = meta['title']?.toString().trim();
        final recordId = SecureScriptStore.recordIdFromMetadata(meta);
        final style = meta['style'] is Map<String, dynamic>
            ? meta['style'] as Map<String, dynamic>
            : const <String, dynamic>{};
        final resolvedTitle =
            title?.isNotEmpty == true ? title! : 'Untitled script';
        _addPayload(
          scripts,
          seen,
          _CloudScriptPayload(
            title: resolvedTitle,
            text: text,
            sourcePath: meta['sourcePath'] as String?,
            sourceType: meta['type']?.toString(),
            sessionId: meta['sessionId']?.toString(),
            historyJson: data?.historyJson,
            historyIndex: (meta['historyIndex'] as num?)?.toInt(),
            fontSize: (style['fontSize'] as num?)?.toDouble(),
            fontFamily: style['fontFamily']?.toString(),
            lineSpacing: (style['lineSpacing'] as num?)?.toDouble(),
            letterSpacing: (style['letterSpacing'] as num?)?.toDouble(),
            wordSpacing: (style['wordSpacing'] as num?)?.toDouble(),
            textAlign: style['textAlign']?.toString(),
            scriptBgColor: (style['scriptBgColor'] as num?)?.toInt(),
            currentWordColor: (style['currentWordColor'] as num?)?.toInt(),
            futureWordColor: (style['futureWordColor'] as num?)?.toInt(),
            isRtl: style['isRtl'] as bool?,
            bookmarks: await _loadProjectBookmarks(
              sessionId: meta['sessionId']?.toString(),
              title: resolvedTitle,
            ),
            identity: recordId ?? meta['sessionId']?.toString() ?? title ?? '',
          ),
        );
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.scriptPayload',
        );
      }
    }
    return scripts;
  }

  bool _activeScriptStillInRecentActivity(
    Script active,
    List<String> recentItems,
  ) {
    final activeSessionId = active.sessionId.trim();
    final activeRecordId = activeSessionId;
    final activePath = _payloadNormalizePath(active.sourcePath);
    final activeTitle = _payloadNormalizeTitle(active.title);
    final activeType = active.sourceType.trim().toLowerCase();
    for (final item in recentItems) {
      try {
        final meta = Map<String, dynamic>.from(jsonDecode(item));
        final recordId = SecureScriptStore.recordIdFromMetadata(meta) ?? '';
        final sessionId = meta['sessionId']?.toString().trim() ?? '';
        if (activeRecordId.isNotEmpty &&
            (recordId == activeRecordId || sessionId == activeRecordId)) {
          return true;
        }
        if (activeSessionId.isNotEmpty && sessionId == activeSessionId) {
          return true;
        }
        final recentPath = _payloadNormalizePath(
          meta['sourcePath']?.toString(),
        );
        if (activePath.isNotEmpty &&
            recentPath.isNotEmpty &&
            activePath == recentPath) {
          return true;
        }
        final recentTitle = _payloadNormalizeTitle(
          meta['title']?.toString() ?? '',
        );
        final recentType = meta['type']?.toString().trim().toLowerCase() ?? '';
        if (activeTitle.isNotEmpty &&
            activeTitle == recentTitle &&
            (activeType.isEmpty ||
                recentType.isEmpty ||
                activeType == recentType)) {
          return true;
        }
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.activeRecentMatch',
        );
      }
    }
    return false;
  }

  Future<ScriptBackupExport> _readableExportFor(
    _CloudScriptPayload script,
  ) async {
    final export = await LocalBackupService.buildScriptExportAsync(
      title: script.title,
      text: script.text,
      sourceType: script.sourceType,
      sourcePath: script.sourcePath,
      fontSize: script.fontSize,
      fontFamily: script.fontFamily,
      textAlign: script.textAlign,
      futureWordColor: script.futureWordColor,
      isRtl: script.isRtl,
      bookmarks: script.bookmarks,
    );
    LocalBackupService.validateExport(export);
    return export;
  }

  ScriptProjectExport _metadataExportFor(
    _CloudScriptPayload script, {
    required String primaryFileName,
  }) {
    return ScriptProjectCodec.buildCompanion(
      primaryFileName: primaryFileName,
      title: script.title,
      rawText: script.text,
      sourceType: script.sourceType,
      sourcePath: script.sourcePath,
      sessionId: script.sessionId,
      historyJson: script.historyJson,
      historyIndex: script.historyIndex,
      fontSize: script.fontSize,
      fontFamily: script.fontFamily,
      lineSpacing: script.lineSpacing,
      letterSpacing: script.letterSpacing,
      wordSpacing: script.wordSpacing,
      textAlign: script.textAlign,
      scriptBgColor: script.scriptBgColor,
      currentWordColor: script.currentWordColor,
      futureWordColor: script.futureWordColor,
      isRtl: script.isRtl,
      bookmarks: script.bookmarks,
    );
  }

  Future<List<ScriptBookmark>> _loadProjectBookmarks({
    required String? sessionId,
    required String title,
  }) async {
    try {
      return ScriptBookmarkService.load(
        ScriptBookmarkService.scopeKey(sessionId, title),
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.projectBookmarks',
        data: {'title': title},
      );
      return const [];
    }
  }

  void _addPayload(
    List<_CloudScriptPayload> scripts,
    Set<String> seen,
    _CloudScriptPayload payload,
  ) {
    final key = _payloadIdentityKey(payload);
    if (seen.add(key)) scripts.add(payload);
  }

  String _payloadIdentityKey(_CloudScriptPayload payload) {
    final path = payload.sourcePath?.trim();
    if (path != null && path.isNotEmpty) {
      return 'path:${_payloadNormalizePath(path)}';
    }
    final title = _payloadNormalizeTitle(payload.title);
    final type = (payload.sourceType ?? '').trim().toLowerCase();
    if (title.isNotEmpty) return 'title:$type:$title';
    return payload.identity.isNotEmpty ? payload.identity : 'untitled';
  }

  String _payloadNormalizePath(String? path) {
    return (path ?? '').trim().replaceAll('/', '\\').toLowerCase();
  }

  String _payloadNormalizeTitle(String title) {
    return title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
