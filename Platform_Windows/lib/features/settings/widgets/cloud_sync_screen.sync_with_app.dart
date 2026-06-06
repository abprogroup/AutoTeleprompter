part of 'cloud_sync_screen.dart';

extension _CloudSyncWithAppActions on _CloudSyncScreenState {
  Future<void> _syncAllBackupsWithApp() async {
    if (_syncingScripts) return;
    final providerIds = [
      for (final provider in CloudConnectionStore.providers)
        if (_accounts.containsKey(provider.id) &&
            _providerSupportsAccount(provider.id))
          provider.id,
    ];
    final hasLocalBackup = _localBackup?.isConnected == true;
    if (providerIds.isEmpty && !hasLocalBackup) {
      _showSnack('Connect a cloud account or choose a Local Backup folder.');
      return;
    }
    final confirmed = await _confirmSyncWithApp('all backup folders');
    if (confirmed != true) return;

    _setSyncingScripts(true);
    _showSnack('Syncing all backup folders with the app...');
    final failures = <String>[];
    try {
      final scripts = await _scriptPayloadsForSync();
      final deleted = await DeletedScriptsService().listLocalDeletedScripts();
      final activeNames = await _activeFileNamesForScripts(scripts, failures);
      final deletedNames = _deletedOriginalFileNames(deleted);

      var localWritten = 0;
      var localRemoved = 0;
      if (hasLocalBackup) {
        localWritten = await _writeLocalBackupScripts(scripts);
        localRemoved = await _removeLocalBackupExtras(
          activeNames: activeNames,
          failures: failures,
        );
      }

      var cloudSaved = 0;
      var cloudDeletedSynced = 0;
      var cloudMovedToDeleted = 0;
      var cloudRemoved = 0;
      for (final providerId in providerIds) {
        for (final script in scripts) {
          final result = await _uploadScriptAndMetadata(
            providerId: providerId,
            script: script,
          );
          if (result.ok) {
            cloudSaved++;
          } else {
            failures.add('${_providerLabel(providerId)}: ${result.message}');
          }
        }

        cloudDeletedSynced += await _syncDeletedScriptsForProvider(
          providerId: providerId,
          deletedScripts: deleted,
          failures: failures,
        );
        final activeCleanup = await _reconcileProviderActiveFiles(
          providerId: providerId,
          activeNames: activeNames,
          deletedNames: deletedNames,
          failures: failures,
        );
        cloudMovedToDeleted += activeCleanup.movedToDeleted;
        cloudRemoved += activeCleanup.removedForever;
        cloudRemoved += await _reconcileProviderDeletedFiles(
          providerId: providerId,
          deletedNames: deletedNames,
          failures: failures,
        );
        await _verifyProviderMatchesApp(
          providerId: providerId,
          activeNames: activeNames,
          deletedNames: deletedNames,
          failures: failures,
        );
      }

      if (failures.isEmpty) {
        _showSnack(
          'All backups match the app: $localWritten local saved, '
          '$localRemoved local removed, $cloudSaved cloud saved, '
          '$cloudDeletedSynced deleted synced, '
          '$cloudMovedToDeleted moved to deleted, $cloudRemoved removed.',
        );
      } else {
        _showSnack(
          'Sync with App finished with ${failures.length} warnings. '
          '${failures.first}',
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.syncAllBackupsWithApp',
      );
      _showSnack('Sync with App failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<void> _syncLocalBackupWithApp() async {
    if (_syncingScripts) return;
    if (!(_localBackup?.isConnected ?? false)) {
      _showSnack('Choose a Local Backup folder first.');
      return;
    }
    final confirmed = await _confirmSyncWithApp('Local Backup');
    if (confirmed != true) return;

    _setSyncingScripts(true);
    final failures = <String>[];
    try {
      final scripts = await _scriptPayloadsForSync();
      final deleted = await DeletedScriptsService().listLocalDeletedScripts();
      final activeNames = await _activeFileNamesForScripts(scripts, failures);
      final written = await _writeLocalBackupScripts(scripts);
      final removed = await _removeLocalBackupExtras(
        activeNames: activeNames,
        failures: failures,
      );
      final deletedCount = deleted.length;
      _showSnack(
        failures.isEmpty
            ? 'Local Backup now matches the app: $written saved, '
                '$deletedCount deleted kept, $removed removed.'
            : 'Local Backup synced with ${failures.length} warnings. '
                '${failures.first}',
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.syncLocalBackupWithApp',
      );
      _showSnack('Local Backup sync with app failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<void> _syncProviderWithApp(String providerId) async {
    if (_syncingScripts) return;
    if (!_accounts.containsKey(providerId)) {
      _showSnack('Reconnect ${_providerLabel(providerId)} first.');
      return;
    }
    final confirmed = await _confirmSyncWithApp(_providerLabel(providerId));
    if (confirmed != true) return;

    _setSyncingScripts(true);
    final failures = <String>[];
    try {
      final scripts = await _scriptPayloadsForSync();
      final deleted = await DeletedScriptsService().listLocalDeletedScripts();
      final activeNames = await _activeFileNamesForScripts(scripts, failures);
      final deletedNames = _deletedOriginalFileNames(deleted);

      var uploaded = 0;
      for (final script in scripts) {
        final result = await _uploadScriptAndMetadata(
          providerId: providerId,
          script: script,
        );
        if (result.ok) {
          uploaded++;
        } else {
          failures.add(result.message);
        }
      }

      final deletedUploaded = await _syncDeletedScriptsForProvider(
        providerId: providerId,
        deletedScripts: deleted,
        failures: failures,
      );
      final activeCleanup = await _reconcileProviderActiveFiles(
        providerId: providerId,
        activeNames: activeNames,
        deletedNames: deletedNames,
        failures: failures,
      );
      final deletedCleanup = await _reconcileProviderDeletedFiles(
        providerId: providerId,
        deletedNames: deletedNames,
        failures: failures,
      );
      await _verifyProviderMatchesApp(
        providerId: providerId,
        activeNames: activeNames,
        deletedNames: deletedNames,
        failures: failures,
      );

      _showSnack(
        failures.isEmpty
            ? '${_providerLabel(providerId)} now matches the app: '
                '$uploaded saved, $deletedUploaded deleted synced, '
                '${activeCleanup.movedToDeleted} moved to deleted, '
                '${activeCleanup.removedForever + deletedCleanup} removed.'
            : '${_providerLabel(providerId)} sync with app finished with '
                '${failures.length} warnings. ${failures.first}',
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.syncProviderWithApp',
        data: {'providerId': providerId},
      );
      _showSnack(
        '${_providerLabel(providerId)} sync with app failed: '
        '${_shortError(error)}',
      );
    } finally {
      _setSyncingScripts(false);
    }
  }

  Future<bool?> _confirmSyncWithApp(String targetLabel) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(
          'Sync $targetLabel with app?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'This makes $targetLabel match AutoTeleprompter. Saved scripts are '
          'updated, app-deleted scripts are moved into Deleted Scripts, and '
          'backup/cloud files that are not in the app will be permanently '
          'removed.',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sync with App'),
          ),
        ],
      ),
    );
  }

  Future<Set<String>> _activeFileNamesForScripts(
    List<_CloudScriptPayload> scripts,
    List<String> failures,
  ) async {
    final names = <String>{};
    for (final script in scripts) {
      try {
        final export = await _readableExportFor(script);
        names.add(_fileKey(export.fileName));
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.syncWithApp.activeName',
          data: {'title': script.title},
        );
        failures.add('${script.title}: ${_shortError(error)}');
      }
    }
    return names;
  }

  Set<String> _deletedOriginalFileNames(List<DeletedScriptEntry> entries) {
    return {
      for (final entry in entries) _fileKey(entry.originalName),
      for (final entry in entries)
        _fileKey(_activeNameFromCloudDeleted(entry.name)),
    }..removeWhere((name) => name.isEmpty);
  }

  Future<int> _removeLocalBackupExtras({
    required Set<String> activeNames,
    required List<String> failures,
  }) async {
    final rootPath = _localBackup?.folderPath.trim() ?? '';
    if (rootPath.isEmpty) return 0;
    final root = Directory(rootPath);
    if (!await root.exists()) return 0;
    var removed = 0;
    final service = LocalBackupService();
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = _syncPathBasename(entity.path);
      if (!_isUserFacingScriptFile(name)) continue;
      final key = _fileKey(name);
      if (activeNames.contains(key)) continue;
      try {
        await service.deleteBackupFileAndHistory(entity.path);
        removed++;
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'cloud.syncWithApp.localRemove',
          data: {'path': entity.path},
        );
        failures.add('Could not remove $name: ${_shortError(error)}');
      }
    }
    return removed;
  }

  Future<void> _verifyProviderMatchesApp({
    required String providerId,
    required Set<String> activeNames,
    required Set<String> deletedNames,
    required List<String> failures,
  }) async {
    final active = await _sync.listScripts(providerId);
    final deleted = await _sync.listDeletedScripts(providerId);
    final activeExtras = [
      for (final file in active)
        if (!activeNames.contains(_fileKey(file.name)) &&
            !deletedNames.contains(_fileKey(file.name)))
          file.name,
    ];
    final deletedExtras = [
      for (final file in deleted)
        if (!deletedNames.contains(
          _fileKey(_activeNameFromCloudDeleted(file.name)),
        ))
          file.name,
    ];
    if (activeExtras.isEmpty && deletedExtras.isEmpty) return;
    final count = activeExtras.length + deletedExtras.length;
    final sample = [
      ...activeExtras,
      ...deletedExtras,
    ].take(2).join(', ');
    failures.add(
      '${_providerLabel(providerId)} still has $count file(s) not matching '
      'the app after sync. Open Synced scripts to review: $sample',
    );
  }

  Future<_ProviderActiveCleanup> _reconcileProviderActiveFiles({
    required String providerId,
    required Set<String> activeNames,
    required Set<String> deletedNames,
    required List<String> failures,
  }) async {
    final files = await _sync.listScripts(providerId);
    var moved = 0;
    var removed = 0;
    for (final file in files) {
      final key = _fileKey(file.name);
      if (activeNames.contains(key)) continue;
      if (deletedNames.contains(key)) {
        final result = await _sync.moveSyncedScriptToDeleted(
          providerId: providerId,
          primaryFileName: file.name,
        );
        if (result.ok) {
          moved++;
        } else {
          failures.add('${file.name}: ${result.message}');
        }
        continue;
      }
      final ok = await _deleteActiveCloudFileForever(file, failures);
      if (ok) removed++;
    }
    return _ProviderActiveCleanup(
      movedToDeleted: moved,
      removedForever: removed,
    );
  }

  Future<int> _reconcileProviderDeletedFiles({
    required String providerId,
    required Set<String> deletedNames,
    required List<String> failures,
  }) async {
    final files = await _sync.listDeletedScripts(providerId);
    var removed = 0;
    for (final file in files) {
      final activeName = _activeNameFromCloudDeleted(file.name);
      if (deletedNames.contains(_fileKey(activeName))) continue;
      final result = await _sync.deleteDeletedScriptPermanently(
        providerId: providerId,
        deletedFileName: file.name,
      );
      if (result.ok) {
        removed++;
      } else {
        failures.add('${file.name}: ${result.message}');
      }
    }
    return removed;
  }

  Future<bool> _deleteActiveCloudFileForever(
    CloudSyncedFile file,
    List<String> failures,
  ) async {
    final delete = await _sync.deleteSyncedScriptPermanently(
      providerId: file.providerId,
      primaryFileName: file.name,
    );
    if (!delete.ok) {
      failures.add('${file.name}: ${delete.message}');
      return false;
    }
    return true;
  }

  bool _isUserFacingScriptFile(String fileName) {
    if (ScriptProjectCodec.isMetadataFileName(fileName)) return false;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tmp') || lower.endsWith('.replace_backup')) {
      return false;
    }
    return RegExp(
      r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages)$',
      caseSensitive: false,
    ).hasMatch(fileName);
  }

  String _fileKey(String fileName) => fileName.trim().toLowerCase();

  String _syncPathBasename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }
}

class _ProviderActiveCleanup {
  final int movedToDeleted;
  final int removedForever;

  const _ProviderActiveCleanup({
    required this.movedToDeleted,
    required this.removedForever,
  });
}
