part of 'local_backup_service.dart';

extension LocalBackupDeletedScripts on LocalBackupService {
  Future<bool> backupDeletedScript({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? historyJson,
    int? historyIndex,
    Map<String, dynamic>? recentMetadata,
  }) async {
    final root = await _backupRoot();
    final deleted = await _deletedRoot();
    if (root == null && deleted == null) return false;
    if (root != null) await _pruneExpiredDeletedBackups(root);
    if (deleted != null) await _pruneExpiredFolder(deleted);
    final stamp = LocalBackupService._timestamp();
    var backedUp = false;

    final movedExisting = root == null || deleted == null
        ? false
        : await _moveExistingBackupToDeleted(
            root: root,
            deleted: deleted,
            title: title,
            text: text,
            sourceType: sourceType,
            sourcePath: sourcePath,
            historyJson: historyJson,
            historyIndex: historyIndex,
            recentMetadata: recentMetadata,
            stamp: stamp,
          );
    if (movedExisting) backedUp = true;

    final readableText = LocalBackupService.exportReadableScriptText(text);
    if (!movedExisting && deleted != null && readableText.trim().isNotEmpty) {
      final export = await _deletedScriptExport(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
      );
      await LocalBackupService.writeExportAtomically(
        File(LocalBackupService._join(
            deleted.path, '${stamp}_${export.fileName}')),
        export,
      );
      await _writeDeletedRestoreMetadata(
        deletedPath: LocalBackupService._join(
          deleted.path,
          '${stamp}_${export.fileName}',
        ),
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
        historyJson: historyJson,
        historyIndex: historyIndex,
        recentMetadata: recentMetadata,
      );
      backedUp = true;
    }
    return backedUp;
  }

  Future<ScriptBackupExport> _deletedScriptExport({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
  }) async {
    try {
      return await LocalBackupService.buildScriptExportAsync(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
      );
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'localBackup.deletedScriptReadableFallback',
        data: {'title': title},
      );
      final readableText = LocalBackupService.exportReadableScriptText(text);
      final baseName = LocalBackupService._safeBaseName(
        title: title,
        sourcePath: sourcePath,
      );
      return ScriptBackupExport(
        fileName: '$baseName.txt',
        mimeType: 'text/plain; charset=utf-8',
        bytes: utf8.encode(readableText),
        readableText: readableText,
        extension: 'txt',
      );
    }
  }

  Future<bool> _moveExistingBackupToDeleted({
    required Directory root,
    required Directory deleted,
    required String title,
    required String text,
    required String stamp,
    String? sourceType,
    String? sourcePath,
    String? historyJson,
    int? historyIndex,
    Map<String, dynamic>? recentMetadata,
  }) async {
    try {
      final export = await LocalBackupService.buildScriptExportAsync(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
      );
      final candidateNames = <String>{
        export.fileName,
        LocalBackupService._safeName(
          LocalBackupService._basename(sourcePath?.trim() ?? ''),
        ),
      }..removeWhere((name) => name.trim().isEmpty || name == 'script');

      File? sourceBackup;
      for (final name in candidateNames) {
        final candidate = File(LocalBackupService._join(root.path, name));
        if (await candidate.exists()) {
          sourceBackup = candidate;
          break;
        }
      }
      if (sourceBackup == null) return false;

      await deleted.create(recursive: true);
      final target = await _uniqueFile(
        Directory(deleted.path),
        '${stamp}_${LocalBackupService._basename(sourceBackup.path)}',
      );
      await _moveFileAtomically(sourceBackup, target);
      await target.setLastModified(DateTime.now());
      await _moveHistoryMetadataRecord(
        oldBackupPath: sourceBackup.path,
        newBackupPath: target.path,
        scriptTitle: title,
      );
      await _writeDeletedRestoreMetadata(
        deletedPath: target.path,
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
        historyJson: historyJson,
        historyIndex: historyIndex,
        recentMetadata: recentMetadata,
      );
      final legacySidecar = File('${sourceBackup.path}.history.json');
      if (await legacySidecar.exists()) {
        await legacySidecar.rename('${target.path}.history.json');
        await _migrateHistorySidecars(root);
      }
      return true;
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'localBackup.moveExistingDeletedBackup',
        data: {'title': title},
      );
      return false;
    }
  }

  Future<void> _moveHistoryMetadataRecord({
    required String oldBackupPath,
    required String newBackupPath,
    required String scriptTitle,
  }) async {
    final oldFile = await _historyMetadataFileForBackupPath(oldBackupPath);
    if (!await oldFile.exists()) return;
    final decoded = jsonDecode(await oldFile.readAsString());
    final historyJson = decoded is Map<String, dynamic>
        ? decoded['historyJson']?.toString() ?? ''
        : '';
    await oldFile.delete();
    if (historyJson.trim().isEmpty) return;
    await _writeHistoryMetadataRecord(
      backupFilePath: newBackupPath,
      scriptTitle: scriptTitle,
      historyJson: historyJson,
    );
  }

  Future<void> _writeDeletedRestoreMetadata({
    required String deletedPath,
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? historyJson,
    int? historyIndex,
    Map<String, dynamic>? recentMetadata,
  }) async {
    final file = await _historyMetadataFileForBackupPath(deletedPath);
    var existing = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) existing = decoded;
      } catch (_) {
        existing = <String, dynamic>{};
      }
    }
    final style = recentMetadata?['style'];
    final metadata = <String, dynamic>{
      ...existing,
      'kind': 'autoteleprompter.deleted_script_restore',
      'backupFilePath': deletedPath,
      'backupFileName': LocalBackupService._basename(deletedPath),
      'scriptTitle': title,
      'sourceType': sourceType ?? existing['sourceType'] ?? 'FILE',
      if (sourcePath != null && sourcePath.trim().isNotEmpty)
        'sourcePath': sourcePath,
      'rawText': text,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if ((historyJson?.trim().isNotEmpty ?? false) ||
          (existing['historyJson']?.toString().trim().isNotEmpty ?? false))
        'historyJson': historyJson?.trim().isNotEmpty == true
            ? historyJson
            : existing['historyJson'],
      if (historyIndex != null) 'historyIndex': historyIndex,
      if (style is Map) 'style': Map<String, dynamic>.from(style),
      if (recentMetadata?['sessionId'] != null)
        'sessionId': recentMetadata!['sessionId'],
    };
    await _writeTextAtomically(file, jsonEncode(metadata));
  }

  Future<void> _moveFileAtomically(File source, File target) async {
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete();
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }

  Future<File> _uniqueFile(Directory directory, String fileName) async {
    final safeName = LocalBackupService._safeName(fileName);
    var candidate = File(LocalBackupService._join(directory.path, safeName));
    if (!await candidate.exists()) return candidate;
    final dot = safeName.lastIndexOf('.');
    final base = dot <= 0 ? safeName : safeName.substring(0, dot);
    final ext = dot <= 0 ? '' : safeName.substring(dot);
    for (var i = 2; i < 1000; i++) {
      candidate = File(LocalBackupService._join(
        directory.path,
        '$base ($i)$ext',
      ));
      if (!await candidate.exists()) return candidate;
    }
    return File(LocalBackupService._join(
      directory.path,
      '${base}_${DateTime.now().microsecondsSinceEpoch}$ext',
    ));
  }
}
