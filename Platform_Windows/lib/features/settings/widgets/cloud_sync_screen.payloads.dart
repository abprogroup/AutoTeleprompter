part of 'cloud_sync_screen.dart';

extension _CloudSyncScreenPayloads on _CloudSyncScreenState {
  Future<List<_CloudScriptPayload>> _scriptPayloadsForSync() async {
    final scripts = <_CloudScriptPayload>[];
    final seen = <String>{};
    final active = ref.read(scriptProvider);
    if (active != null && active.rawText.trim().isNotEmpty) {
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
          bookmarks: await _loadProjectBookmarks(
            sessionId: active.sessionId,
            title: active.title,
          ),
          identity: active.sessionId,
        ),
      );
    }

    final secureStore = SecureScriptStore();
    for (final item in ref.read(settingsProvider).recentScripts) {
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

  ScriptBackupExport _readableExportFor(_CloudScriptPayload script) {
    return LocalBackupService.buildScriptExport(
      title: script.title,
      text: script.text,
      sourceType: script.sourceType,
      sourcePath: script.sourcePath,
      bookmarks: script.bookmarks,
    );
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
    final key = payload.identity.isNotEmpty ? payload.identity : payload.title;
    if (seen.add(key)) scripts.add(payload);
  }
}
