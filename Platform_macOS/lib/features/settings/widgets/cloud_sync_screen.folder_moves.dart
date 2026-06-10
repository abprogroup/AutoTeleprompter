part of 'cloud_sync_screen.dart';

extension _CloudSyncScreenFolderMoves on _CloudSyncScreenState {
  Future<void> _setDeletedFolderOverride(bool enabled) async {
    if (!enabled) {
      final oldPath = await _store.resolveDeletedScriptsFolderPath();
      await _store.setDeletedScriptsCustomFolderEnabled(false);
      final newPath = await _store.resolveDeletedScriptsFolderPath();
      await _maybeMoveExistingFolderContents(
        oldPath: oldPath,
        newPath: newPath,
        title: 'Move deleted-script backups?',
        message:
            'Move existing deleted-script backups into the default Local Backup '
            'Deleted Scripts folder?',
      );
      await _loadConnections();
      _showSnack('Deleted scripts now use the Local Backup folder.');
      return;
    }
    await _store.setDeletedScriptsCustomFolderEnabled(true);
    await _loadConnections();
    _showSnack('Choose a deleted scripts folder when you are ready.');
  }

  Future<void> _chooseDeletedScriptsFolder() async {
    final oldFolder = await _store.resolveDeletedScriptsFolderPath();
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose deleted scripts folder',
    );
    if (folder == null) return;
    final directory = Directory(folder);
    if (!await directory.exists()) {
      _showSnack('Selected folder does not exist.');
      return;
    }
    await _maybeMoveExistingFolderContents(
      oldPath: oldFolder,
      newPath: folder,
      title: 'Move existing deleted-script backups?',
      message: 'Move existing deleted-script backups to this separate folder?',
    );
    await _store.setDeletedScriptsCustomFolderEnabled(true);
    await _store.setDeletedScriptsCustomFolderPath(folder);
    await _loadConnections();
    _showSnack('Deleted scripts folder linked.');
  }

  Future<void> _forgetDeletedScriptsFolder() async {
    await _store.disconnectDeletedScriptsCustomFolder();
    await _loadConnections();
    _showSnack('Deleted scripts custom folder forgotten.');
  }

  Future<void> _maybeMoveExistingFolderContents({
    required String oldPath,
    required String newPath,
    required String title,
    required String message,
  }) async {
    final sourcePath = CloudConnectionStore.normalizePath(oldPath);
    final targetPath = CloudConnectionStore.normalizePath(newPath);
    if (sourcePath.isEmpty || targetPath.isEmpty) return;
    if (_samePath(sourcePath, targetPath)) return;
    final source = Directory(sourcePath);
    if (!await source.exists() || !await _hasDirectoryEntries(source)) return;
    final confirmed = await _confirmMoveFolderContents(
      title: title,
      message: message,
      oldPath: sourcePath,
      newPath: targetPath,
    );
    if (confirmed != true) return;
    try {
      await _moveDirectoryContents(source, Directory(targetPath));
      _showSnack('Existing files moved to the new folder.');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.moveFolderContents',
        data: {'oldPath': sourcePath, 'newPath': targetPath},
      );
      _showSnack('Could not move existing files: ${_shortError(error)}');
    }
  }

  Future<bool?> _confirmMoveFolderContents({
    required String title,
    required String message,
    required String oldPath,
    required String newPath,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(
          '$message\n\nFrom:\n$oldPath\n\nTo:\n$newPath',
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Leave files'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.drive_file_move_outline),
            label: const Text('Move files'),
          ),
        ],
      ),
    );
  }

  Future<bool> _hasDirectoryEntries(Directory directory) async {
    await for (final _ in directory.list()) {
      return true;
    }
    return false;
  }

  Future<void> _moveDirectoryContents(
    Directory source,
    Directory target,
  ) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      if (_samePath(entity.path, target.path)) continue;
      final targetEntityPath = CloudConnectionStore.joinPath(
        target.path,
        entity.uri.pathSegments.last,
      );
      if (entity is File) {
        await _moveFile(entity, File(targetEntityPath));
      } else if (entity is Directory) {
        await _moveDirectory(entity, Directory(targetEntityPath));
      }
    }
  }

  Future<void> _moveDirectory(Directory source, Directory target) async {
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      try {
        await source.rename(target.path);
        return;
      } on FileSystemException {
        // Fall through to copy/delete for cross-volume moves.
      }
    }
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      final targetEntityPath = CloudConnectionStore.joinPath(
        target.path,
        entity.uri.pathSegments.last,
      );
      if (entity is File) {
        await _moveFile(entity, File(targetEntityPath));
      } else if (entity is Directory) {
        await _moveDirectory(entity, Directory(targetEntityPath));
      }
    }
    if (await source.exists()) await source.delete(recursive: true);
  }

  Future<void> _moveFile(File source, File target) async {
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      final unique = await _uniqueMoveTarget(target);
      target = unique;
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }

  Future<File> _uniqueMoveTarget(File file) async {
    final path = file.path;
    final separator = Platform.pathSeparator;
    final folder = path.contains(separator)
        ? path.substring(0, path.lastIndexOf(separator))
        : '';
    final name = path.contains(separator)
        ? path.substring(path.lastIndexOf(separator) + 1)
        : path;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    for (var i = 2; i < 1000; i++) {
      final candidate = File(CloudConnectionStore.joinPath(
        folder,
        '$base ($i)$ext',
      ));
      if (!await candidate.exists()) return candidate;
    }
    return File(CloudConnectionStore.joinPath(
      folder,
      '${base}_${DateTime.now().microsecondsSinceEpoch}$ext',
    ));
  }

  bool _samePath(String left, String right) {
    String clean(String value) {
      final normalized = Directory(value)
          .absolute
          .path
          .replaceAll('/', '\\')
          .replaceAll(RegExp(r'\\+$'), '')
          .toLowerCase();
      return normalized;
    }

    return clean(left) == clean(right);
  }
}
