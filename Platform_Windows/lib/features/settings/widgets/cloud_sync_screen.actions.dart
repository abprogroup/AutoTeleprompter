part of 'cloud_sync_screen.dart';

extension _CloudSyncScreenActions on _CloudSyncScreenState {
  Future<void> _uploadLocalBackupScripts() async {
    if (_syncingScripts) return;
    final scripts = await _scriptPayloadsForSync();
    if (scripts.isEmpty) {
      _showSnack('No saved scripts are available to back up.');
      return;
    }
    final selected = await _chooseScriptsForCloudAction(
      scripts: scripts,
      title: 'Back up scripts locally',
      actionLabel: 'Back up selected',
      defaultSelectAll: false,
    );
    if (selected == null || selected.isEmpty) return;

    _setSyncingScripts(true);
    try {
      final count = await _writeLocalBackupScripts(selected);
      _showSnack('Backed up $count scripts to Local Backup.');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.uploadLocalBackupScripts',
      );
      _showSnack('Local Backup failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<void> _showLocalBackupScripts() async {
    final folder = _localBackup?.folderPath.trim() ?? '';
    if (folder.isEmpty) return;
    final files = <File>[];
    try {
      await LocalBackupService().migrateHistorySidecarsFromBackupFolder();
      final directory = Directory(folder);
      if (await directory.exists()) {
        await for (final entity in directory.list()) {
          if (entity is! File) continue;
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.rtf') ||
              lower.endsWith('.docx') ||
              lower.endsWith('.doc') ||
              lower.endsWith('.txt') ||
              lower.endsWith('.text') ||
              lower.endsWith('.log') ||
              lower.endsWith('.md') ||
              lower.endsWith('.pdf') ||
              lower.endsWith('.odt') ||
              lower.endsWith('.pages')) {
            files.add(entity);
          }
        }
      }
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.localBackupList',
      );
      _showSnack('Could not list Local Backup scripts.');
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          'Local Backup scripts',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 560,
          child: files.isEmpty
              ? const Text(
                  'No backed-up scripts are in this folder yet.',
                  style: TextStyle(color: Colors.white70),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final stat = file.statSync();
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          file.uri.pathSegments.last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          '${stat.modified}',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openFolder(folder);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else {
        await Process.run('open', [path]);
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.openFolder',
      );
      _showSnack('Could not open the folder.');
    }
  }

  Future<void> _connectProviderAccount(CloudProviderDefinition provider) async {
    final result = await _oauth.connect(provider);
    await _loadConnections();
    if (!mounted) return;
    if (result.connected) {
      _showSnack(result.message);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(
          result.missingCredentials
              ? '${provider.label} needs app credentials'
              : '${provider.label} account connection',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          result.message,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _chooseLocalBackupFolder();
            },
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose Local Backup folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectProviderAccount(String providerId) async {
    await _oauth.disconnect(providerId);
    await _loadConnections();
    _showSnack('Cloud account disconnected.');
  }

  Future<void> _setAutoSyncScripts(bool enabled) async {
    if (enabled && _accounts.isEmpty && !(_localBackup?.isConnected ?? false)) {
      _showSnack(
          'Connect a cloud account or choose a Local Backup folder first.');
      return;
    }
    await ref.read(settingsProvider.notifier).setCloudAutoSyncOnSave(enabled);
    _showSnack(
      enabled
          ? 'Script auto-sync enabled. Changes sync every 30 seconds and before reading/recording.'
          : 'Script auto-sync disabled.',
    );
  }

  Future<void> _setRecordingAutoBackup(bool enabled) async {
    if (enabled && _accounts.isEmpty) {
      _showSnack(
          'Connect Google Drive or Dropbox before uploading recordings.');
      return;
    }
    await ref.read(settingsProvider.notifier).setRecordingAutoBackup(enabled);
    _showSnack(
      enabled
          ? 'Recording cloud upload enabled for completed recordings.'
          : 'Recording cloud upload disabled.',
    );
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
      defaultSelectAll: false,
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

  Future<void> _syncAllScripts() async {
    if (_syncingScripts) return;
    final providers = [
      for (final provider in CloudConnectionStore.providers)
        if (_accounts.containsKey(provider.id) &&
            _providerSupportsAccount(provider.id))
          provider.id,
    ];
    final hasLocalBackup = _localBackup?.isConnected == true;
    if (providers.isEmpty && !hasLocalBackup) {
      _showSnack('Connect a cloud account or choose a Local Backup folder.');
      return;
    }

    final availableScripts = await _scriptPayloadsForSync();
    if (availableScripts.isEmpty) {
      _showSnack('No saved scripts are available to sync.');
      return;
    }
    final scripts = await _chooseScriptsForCloudAction(
      scripts: availableScripts,
      title: 'Sync scripts',
      actionLabel: 'Sync selected',
      defaultSelectAll: true,
    );
    if (scripts == null || scripts.isEmpty) return;

    _setSyncingScripts(true);
    _showSnack('Syncing ${scripts.length} saved scripts...');
    final cloudOkByProvider = {
      for (final providerId in providers) providerId: 0,
    };
    final cloudFailedByProvider = {
      for (final providerId in providers) providerId: 0,
    };
    final failures = <String>[];
    try {
      for (final script in scripts) {
        for (final providerId in providers) {
          final result = await _uploadScriptAndMetadata(
            providerId: providerId,
            script: script,
          );
          if (result.ok) {
            cloudOkByProvider[providerId] =
                (cloudOkByProvider[providerId] ?? 0) + 1;
          } else {
            cloudFailedByProvider[providerId] =
                (cloudFailedByProvider[providerId] ?? 0) + 1;
            failures.add('${_providerLabel(providerId)}: ${result.message}');
          }
        }
      }

      var localCount = 0;
      if (hasLocalBackup) {
        try {
          localCount = await _writeLocalBackupScripts(scripts);
        } catch (error, stack) {
          LightweightDiagnostics.instance.recordError(
            error,
            stack,
            source: 'cloud.localBackupSync',
          );
          failures.add('Local backup failed: ${_shortError(error)}');
        }
      }

      final targetText = [
        for (final providerId in providers)
          '${_providerLabel(providerId)}: ${cloudOkByProvider[providerId] ?? 0}',
        if (localCount > 0) '$localCount local backups',
      ].join(', ');
      final cloudFailed = cloudFailedByProvider.values
          .fold<int>(0, (sum, count) => sum + count);
      if (failures.isEmpty && cloudFailed == 0) {
        _showSnack('Synced ${scripts.length} scripts ($targetText).');
      } else {
        _showSnack(
          'Sync finished ($targetText) with $cloudFailed cloud failures. '
          '${failures.first}',
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.syncAllScripts',
      );
      _showSnack('Cloud sync failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<List<_CloudScriptPayload>?> _chooseScriptsForCloudAction({
    required List<_CloudScriptPayload> scripts,
    required String title,
    required String actionLabel,
    required bool defaultSelectAll,
  }) async {
    final active = ref.read(scriptProvider);
    final activeIdentity = active?.sessionId.trim() ?? '';
    final selected = <String>{
      if (defaultSelectAll)
        for (final script in scripts) script.identity
      else if (activeIdentity.isNotEmpty &&
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

  String _providerLabel(String providerId) {
    return switch (providerId) {
      CloudConnectionStore.googleDrive => 'Google Drive',
      CloudConnectionStore.dropbox => 'Dropbox',
      _ => providerId,
    };
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

  Future<int> _writeLocalBackupScripts(
    List<_CloudScriptPayload> scripts,
  ) async {
    if (!(_localBackup?.isConnected ?? false)) return 0;
    final backup = LocalBackupService();
    var written = 0;
    for (final script in scripts) {
      try {
        final ok = await backup.backupScript(
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
        if (ok) written++;
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.writeLocalBackupScript',
          data: {'title': script.title},
        );
      }
    }
    return written;
  }

  Future<void> _showSyncedScripts(CloudProviderDefinition provider) async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(
          '${provider.label} scripts',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<CloudSyncedFile>>(
            future: _sync.listScripts(provider.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFBF00),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Could not list scripts: ${_shortError(snapshot.error!)}',
                  style: const TextStyle(color: Colors.white70, height: 1.35),
                );
              }
              final files = snapshot.data ?? const <CloudSyncedFile>[];
              if (files.isEmpty) {
                return const Text(
                  'No scripts are synced in the AutoTeleprompter app folder yet.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        file.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        file.modifiedAtIso ?? 'Cloud script',
                        style: const TextStyle(color: Colors.white38),
                      ),
                      trailing: TextButton(
                        onPressed: () => _downloadSyncedScript(file),
                        child: const Text('Download'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSyncedScript(CloudSyncedFile file) async {
    try {
      final metadataText = await _sync.downloadScriptMetadata(
        providerId: file.providerId,
        primaryFileName: file.name,
      );
      final project = metadataText == null || metadataText.isEmpty
          ? null
          : ScriptProjectCodec.tryDecode(metadataText);
      if (project != null) {
        await _restoreProjectFromCloud(project);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        _showSnack('Downloaded ${file.name}.');
        return;
      }

      final lowerName = file.name.toLowerCase();
      if (lowerName.endsWith('.rtf') ||
          lowerName.endsWith('.doc') ||
          lowerName.endsWith('.docx')) {
        _showSnack(
          'Cloud metadata is missing for ${file.name}; '
          'the readable file is still available in the cloud.',
        );
        return;
      }

      final text = await _sync.downloadScript(
        providerId: file.providerId,
        fileId: file.id,
      );
      if (text == null || text.isEmpty) {
        _showSnack('Cloud download failed.');
        return;
      }
      final legacyProject = ScriptProjectCodec.tryDecode(text);
      if (legacyProject != null) {
        await _restoreProjectFromCloud(legacyProject);
      } else {
        ref.read(scriptProvider.notifier).loadText(
              text,
              title: file.name,
              sourceType: 'CLOUD',
              sessionId: 'cloud_${DateTime.now().microsecondsSinceEpoch}',
            );
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('Downloaded ${file.name}.');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.downloadSyncedScript',
      );
      _showSnack('Cloud download failed: ${_shortError(error)}');
    }
  }

  Future<void> _restoreProjectFromCloud(ScriptProjectData project) async {
    await ScriptBookmarkService.save(
      ScriptBookmarkService.scopeKey(project.sessionId, project.title),
      project.bookmarks,
    );
    ref.read(scriptProvider.notifier).loadText(
          project.rawText,
          title: project.title,
          sourceType: project.sourceType,
          sessionId: project.sessionId,
          historyJson: project.historyJson,
          historyIndex: project.historyIndex,
          fontSize: project.fontSize,
          fontFamily: project.fontFamily,
          lineSpacing: project.lineSpacing,
          letterSpacing: project.letterSpacing,
          wordSpacing: project.wordSpacing,
          textAlign: project.textAlign,
          scriptBgColor: project.scriptBgColor,
          currentWordColor: project.currentWordColor,
          futureWordColor: project.futureWordColor,
        );
  }
}
