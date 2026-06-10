part of 'cloud_sync_screen.dart';

class _CloudScriptsDialogData {
  final List<CloudSyncedFile> active;
  final List<CloudSyncedFile> deleted;

  const _CloudScriptsDialogData({
    required this.active,
    required this.deleted,
  });

  bool get isEmpty => active.isEmpty && deleted.isEmpty;
}

extension _CloudSyncScreenSyncedScriptsDialog on _CloudSyncScreenState {
  Future<_CloudScriptsDialogData> _loadSyncedScriptsDialogData(
    String providerId,
  ) async {
    final active = await _sync.listScripts(providerId);
    final deleted = await _sync.listDeletedScripts(providerId);
    return _CloudScriptsDialogData(active: active, deleted: deleted);
  }

  Future<void> _showSyncedScripts(CloudProviderDefinition provider) async {
    var future = _loadSyncedScriptsDialogData(provider.id);
    final selected = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void refresh() {
              setDialogState(() {
                selected.clear();
                future = _loadSyncedScriptsDialogData(provider.id);
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF151515),
              title: Text(
                '${provider.label} scripts',
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 640,
                child: FutureBuilder<_CloudScriptsDialogData>(
                  future: future,
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
                        'Could not list scripts: '
                        '${_shortError(snapshot.error!)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      );
                    }

                    final data = snapshot.data ??
                        const _CloudScriptsDialogData(
                          active: [],
                          deleted: [],
                        );
                    if (data.isEmpty) {
                      return const Text(
                        'No scripts are synced in the AutoTeleprompter app '
                        'folder yet.',
                        style: TextStyle(color: Colors.white70, height: 1.35),
                      );
                    }

                    final activeSelected = [
                      for (final file in data.active)
                        if (selected.contains(_cloudListKey('active', file)))
                          file,
                    ];
                    final deletedSelected = [
                      for (final file in data.deleted)
                        if (selected.contains(_cloudListKey('deleted', file)))
                          file,
                    ];
                    final selectableKeys = [
                      for (final file in data.active)
                        _cloudListKey('active', file),
                      for (final file in data.deleted)
                        _cloudListKey('deleted', file),
                    ];

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => setDialogState(() {
                                selected
                                  ..clear()
                                  ..addAll(selectableKeys);
                              }),
                              icon: const Icon(Icons.done_all),
                              label: const Text('Select all'),
                            ),
                            TextButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => setDialogState(selected.clear),
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear all'),
                            ),
                            Text(
                              '${selected.length}/${selectableKeys.length} '
                              'selected',
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: activeSelected.isEmpty
                                  ? null
                                  : () => _runCloudDialogAction(
                                        refresh: refresh,
                                        successMessage:
                                            'Downloaded active scripts',
                                        action: () => _downloadCloudFiles(
                                          activeSelected,
                                        ),
                                      ),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Download selected'),
                            ),
                            TextButton.icon(
                              onPressed: activeSelected.isEmpty
                                  ? null
                                  : () => _runCloudDialogAction(
                                        refresh: refresh,
                                        successMessage:
                                            'Moved scripts to Deleted Scripts',
                                        action: () => _moveCloudFilesToDeleted(
                                          activeSelected,
                                        ),
                                      ),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Move to deleted'),
                            ),
                            TextButton.icon(
                              onPressed: deletedSelected.isEmpty
                                  ? null
                                  : () => _runCloudDialogAction(
                                        refresh: refresh,
                                        successMessage:
                                            'Restored deleted scripts',
                                        action: () => _restoreCloudDeletedFiles(
                                          deletedSelected,
                                        ),
                                      ),
                              icon: const Icon(Icons.restore_from_trash),
                              label: const Text('Restore selected'),
                            ),
                            TextButton.icon(
                              onPressed: deletedSelected.isEmpty
                                  ? null
                                  : () => _deleteCloudDeletedFilesWithConfirm(
                                        deletedSelected,
                                        refresh: refresh,
                                      ),
                              icon: const Icon(Icons.delete_forever_outlined),
                              label: const Text('Delete forever'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 420),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              _cloudListSectionTitle('Synced scripts'),
                              if (data.active.isEmpty)
                                _cloudListEmpty('No active synced scripts.')
                              else
                                for (final file in data.active)
                                  _cloudListRow(
                                    bucket: 'active',
                                    file: file,
                                    selected: selected,
                                    setDialogState: setDialogState,
                                    primaryLabel: 'Download',
                                    primaryIcon: Icons.download_outlined,
                                    onPrimary: () => _runCloudDialogAction(
                                      refresh: refresh,
                                      successMessage: 'Downloaded script',
                                      action: () => _downloadCloudFiles([file]),
                                    ),
                                    deleteTooltip: 'Move to Deleted Scripts',
                                    onDelete: () => _runCloudDialogAction(
                                      refresh: refresh,
                                      successMessage:
                                          'Moved script to Deleted Scripts',
                                      action: () =>
                                          _moveCloudFilesToDeleted([file]),
                                    ),
                                  ),
                              const SizedBox(height: 14),
                              _cloudListSectionTitle('Deleted scripts'),
                              if (data.deleted.isEmpty)
                                _cloudListEmpty('No cloud deleted scripts.')
                              else
                                for (final file in data.deleted)
                                  _cloudListRow(
                                    bucket: 'deleted',
                                    file: file,
                                    selected: selected,
                                    setDialogState: setDialogState,
                                    primaryLabel: 'Restore',
                                    primaryIcon: Icons.restore_from_trash,
                                    onPrimary: () => _runCloudDialogAction(
                                      refresh: refresh,
                                      successMessage: 'Restored script',
                                      action: () =>
                                          _restoreCloudDeletedFiles([file]),
                                    ),
                                    deleteTooltip: 'Delete permanently',
                                    onDelete: () =>
                                        _deleteCloudDeletedFilesWithConfirm(
                                      [file],
                                      refresh: refresh,
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _cloudListSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFBF00),
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _cloudListEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white38),
      ),
    );
  }

  Widget _cloudListRow({
    required String bucket,
    required CloudSyncedFile file,
    required Set<String> selected,
    required StateSetter setDialogState,
    required String primaryLabel,
    required IconData primaryIcon,
    required VoidCallback onPrimary,
    required String deleteTooltip,
    required VoidCallback onDelete,
  }) {
    final key = _cloudListKey(bucket, file);
    final checked = selected.contains(key);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: checked,
            activeColor: const Color(0xFFFFBF00),
            checkColor: Colors.black,
            onChanged: (value) => setDialogState(() {
              if (value ?? false) {
                selected.add(key);
              } else {
                selected.remove(key);
              }
            }),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  file.modifiedAtIso ?? 'Cloud script',
                  style: const TextStyle(color: Colors.white38),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onPrimary,
            icon: Icon(primaryIcon, size: 18),
            label: Text(primaryLabel),
          ),
          Tooltip(
            message: deleteTooltip,
            child: IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: const Color(0xFFFFBF00),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runCloudDialogAction({
    required Future<int> Function() action,
    required VoidCallback refresh,
    required String successMessage,
  }) async {
    final count = await action();
    if (!mounted) return;
    refresh();
    _showSnack('$successMessage: $count.');
  }

  Future<void> _deleteCloudDeletedFilesWithConfirm(
    List<CloudSyncedFile> files, {
    required VoidCallback refresh,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          'Delete cloud scripts forever?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          files.length == 1
              ? 'This permanently deletes "${files.first.name}" from the '
                  'cloud Deleted Scripts folder.'
              : 'This permanently deletes ${files.length} scripts from the '
                  'cloud Deleted Scripts folder.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runCloudDialogAction(
      refresh: refresh,
      successMessage: 'Deleted cloud scripts forever',
      action: () => _deleteCloudDeletedFiles(files),
    );
  }

  Future<int> _downloadCloudFiles(List<CloudSyncedFile> files) async {
    var downloaded = 0;
    for (final file in files) {
      final ok = await _downloadSyncedScript(
        file,
        closeDialog: false,
        showSuccess: false,
      );
      if (ok) downloaded++;
    }
    return downloaded;
  }

  Future<int> _moveCloudFilesToDeleted(List<CloudSyncedFile> files) async {
    var moved = 0;
    for (final file in files) {
      final result = await _sync.moveSyncedScriptToDeleted(
        providerId: file.providerId,
        primaryFileName: file.name,
      );
      if (result.ok) {
        moved++;
      } else {
        _showSnack(result.message);
      }
    }
    return moved;
  }

  Future<int> _restoreCloudDeletedFiles(List<CloudSyncedFile> files) async {
    var restored = 0;
    for (final file in files) {
      final result = await _sync.restoreDeletedScript(
        providerId: file.providerId,
        deletedFileName: file.name,
        activeFileName: _activeNameFromDeletedCloudFile(file.name),
      );
      if (result.ok) {
        restored++;
      } else {
        _showSnack(result.message);
      }
    }
    return restored;
  }

  Future<int> _deleteCloudDeletedFiles(List<CloudSyncedFile> files) async {
    var deleted = 0;
    for (final file in files) {
      final result = await _sync.deleteDeletedScriptPermanently(
        providerId: file.providerId,
        deletedFileName: file.name,
      );
      if (result.ok) {
        deleted++;
      } else {
        _showSnack(result.message);
      }
    }
    return deleted;
  }

  Future<bool> _downloadSyncedScript(
    CloudSyncedFile file, {
    bool closeDialog = true,
    bool showSuccess = true,
  }) async {
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
        if (!mounted) return false;
        if (closeDialog) Navigator.of(context, rootNavigator: true).pop();
        if (showSuccess) _showSnack('Downloaded ${file.name}.');
        return true;
      }

      final lowerName = file.name.toLowerCase();
      if (lowerName.endsWith('.rtf') ||
          lowerName.endsWith('.doc') ||
          lowerName.endsWith('.docx')) {
        _showSnack(
          'Cloud metadata is missing for ${file.name}; '
          'the readable file is still available in the cloud.',
        );
        return false;
      }

      final text = await _sync.downloadScript(
        providerId: file.providerId,
        fileId: file.id,
      );
      if (text == null || text.isEmpty) {
        _showSnack('Cloud download failed.');
        return false;
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
      if (!mounted) return false;
      if (closeDialog) Navigator.of(context, rootNavigator: true).pop();
      if (showSuccess) _showSnack('Downloaded ${file.name}.');
      return true;
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.downloadSyncedScript',
      );
      _showSnack('Cloud download failed: ${_shortError(error)}');
      return false;
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

  String _cloudListKey(String bucket, CloudSyncedFile file) {
    return '$bucket::${file.providerId}::${file.id}::${file.name}';
  }

  String _activeNameFromDeletedCloudFile(String fileName) {
    return fileName.replaceFirst(RegExp(r'^\d{8}_\d{6}_'), '');
  }
}
