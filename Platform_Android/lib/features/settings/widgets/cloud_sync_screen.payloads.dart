part of 'cloud_sync_screen.dart';

class _CloudScriptPayload {
  final String title;
  final String text;
  final String? sourcePath;
  final String? sourceType;
  final String? sessionId;
  final String? historyJson;
  final int? historyIndex;
  final double? fontSize;
  final String? fontFamily;
  final double? lineSpacing;
  final double? letterSpacing;
  final double? wordSpacing;
  final String? textAlign;
  final int? scriptBgColor;
  final int? currentWordColor;
  final int? futureWordColor;
  final bool? isRtl;
  final List<ScriptBookmark> bookmarks;
  final String identity;

  const _CloudScriptPayload({
    required this.title,
    required this.text,
    required this.sourcePath,
    required this.sourceType,
    required this.sessionId,
    required this.historyJson,
    required this.historyIndex,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.textAlign,
    required this.scriptBgColor,
    required this.currentWordColor,
    required this.futureWordColor,
    required this.isRtl,
    required this.bookmarks,
    required this.identity,
  });
}

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

  Future<void> _uploadSelectedScripts(String providerId) async {
    if (_syncingScripts) return;
    final scripts = await _scriptPayloadsForSync();
    if (scripts.isEmpty) {
      _showSnack('No saved scripts are available to upload.');
      return;
    }
    final selected = await _chooseScriptsForCloudAction(
      scripts: scripts,
      title: 'Upload scripts',
      actionLabel: 'Upload selected',
    );
    if (selected == null || selected.isEmpty) return;

    _setSyncingScripts(true);
    _showSnack('Uploading ${selected.length} selected scripts...');
    var ok = 0;
    final failures = <String>[];
    try {
      for (final script in selected) {
        final result = await _uploadScriptAndMetadata(
          providerId: providerId,
          script: script,
        );
        if (result.ok) {
          ok++;
        } else {
          failures.add(result.message);
        }
      }
      if (failures.isEmpty) {
        _showSnack('Uploaded $ok scripts.');
      } else {
        _showSnack(
          'Uploaded $ok scripts; ${failures.length} failed. '
          '${failures.first}',
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.uploadSelectedScripts',
      );
      _showSnack('Cloud upload failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<CloudSyncResult> _uploadScriptAndMetadata({
    required String providerId,
    required _CloudScriptPayload script,
  }) async {
    late final ScriptBackupExport readable;
    try {
      readable = await _readableExportFor(script);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.prepareReadableExport',
        data: {'title': script.title, 'providerId': providerId},
      );
      return CloudSyncResult(
        ok: false,
        message: '${script.title}: ${_shortError(error)}',
      );
    }
    if (readable.readableText.trim().isEmpty) {
      return CloudSyncResult(
        ok: false,
        message: '${script.title} has no readable script text to upload.',
      );
    }

    final primaryResult = await _sync.uploadScript(
      providerId: providerId,
      title: script.title,
      text: readable.readableText,
      fileName: readable.fileName,
      bytes: readable.bytes,
      mimeType: readable.mimeType,
      replaceExisting: true,
    );
    if (!primaryResult.ok) return primaryResult;

    final metadata = _metadataExportFor(
      script,
      primaryFileName: readable.fileName,
    );
    final metadataResult = await _sync.uploadScript(
      providerId: providerId,
      title: script.title,
      text: script.text,
      fileName: metadata.fileName,
      bytes: metadata.bytes,
      mimeType: metadata.mimeType,
      replaceExisting: true,
    );
    if (!metadataResult.ok) {
      return CloudSyncResult(
        ok: false,
        message: 'Uploaded ${readable.fileName}, but metadata restore failed: '
            '${metadataResult.message}',
      );
    }

    await _sync.cleanupLegacyScriptArtifacts(
      providerId: providerId,
      primaryFileName: readable.fileName,
    );

    return primaryResult;
  }

  Future<List<_CloudScriptPayload>?> _chooseScriptsForCloudAction({
    required List<_CloudScriptPayload> scripts,
    required String title,
    required String actionLabel,
  }) async {
    final active = ref.read(scriptProvider);
    final activeIdentity = active?.sessionId.trim() ?? '';
    final selected = <String>{
      if (activeIdentity.isNotEmpty &&
          scripts.any((script) => script.identity == activeIdentity))
        activeIdentity
      else if (scripts.length == 1)
        scripts.first.identity,
    };

    return showDialog<List<_CloudScriptPayload>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void selectAll() => setDialogState(() {
                selected
                  ..clear()
                  ..addAll(scripts.map((script) => script.identity));
              });
          void clearAll() => setDialogState(selected.clear);

          return AlertDialog(
            backgroundColor: const Color(0xFF151515),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 620,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: selectAll,
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('Select all'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: clearAll,
                        icon: const Icon(Icons.clear_all_rounded),
                        label: const Text('Clear all'),
                      ),
                      const Spacer(),
                      Text(
                        '${selected.length}/${scripts.length} selected',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: scripts.length,
                      itemBuilder: (context, index) {
                        final script = scripts[index];
                        final checked = selected.contains(script.identity);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (value) => setDialogState(() {
                            if (value ?? false) {
                              selected.add(script.identity);
                            } else {
                              selected.remove(script.identity);
                            }
                          }),
                          activeColor: const Color(0xFFFFBF00),
                          checkColor: Colors.black,
                          title: Text(
                            script.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _scriptPayloadSubtitle(script),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          [
                            for (final script in scripts)
                              if (selected.contains(script.identity)) script,
                          ],
                        ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                ),
                child: Text(actionLabel),
              ),
            ],
          );
        },
      ),
    );
  }

  String _scriptPayloadSubtitle(_CloudScriptPayload script) {
    final source = script.sourcePath?.trim() ?? '';
    final readable = LocalBackupService.exportReadableScriptText(script.text);
    final words = readable
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .length;
    if (source.isEmpty) return '$words words';
    final fileName = source.split(RegExp(r'[\\/]')).last;
    return '$words words - $fileName';
  }
}
