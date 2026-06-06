import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RuntimeFileStorage {
  const RuntimeFileStorage._();

  static Future<Directory> visibleFolder(
    String folderName, {
    bool migrateFromAppSupport = true,
  }) async {
    final directory = Directory(
      '${_runtimeRoot().path}${Platform.pathSeparator}$folderName',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    if (migrateFromAppSupport) {
      await _migrateAppSupportFolder(folderName, directory);
    }
    return directory;
  }

  static Directory _runtimeRoot() {
    final executable = File(Platform.resolvedExecutable);
    return executable.parent;
  }

  static Future<void> _migrateAppSupportFolder(
    String folderName,
    Directory visibleDirectory,
  ) async {
    final support = await getApplicationSupportDirectory();
    final legacy = Directory(
      '${support.path}${Platform.pathSeparator}$folderName',
    );
    if (!await legacy.exists()) return;
    if (_samePath(legacy.path, visibleDirectory.path)) return;

    for (final entity in legacy.listSync()) {
      final target = _uniquePath(
        '${visibleDirectory.path}${Platform.pathSeparator}'
        '${_basename(entity.path)}',
      );
      try {
        await entity.rename(target);
      } catch (_) {
        await _copyEntity(entity, target);
        await entity.delete(recursive: true);
      }
    }

    try {
      final isEmpty = legacy.listSync().isEmpty;
      if (isEmpty) await legacy.delete();
    } catch (_) {
      // Leaving a non-empty or locked legacy folder is safer than deleting it.
    }
  }

  static Future<void> _copyEntity(
      FileSystemEntity entity, String target) async {
    if (entity is File) {
      await File(target).writeAsBytes(await entity.readAsBytes(), flush: true);
      return;
    }
    if (entity is Directory) {
      final targetDir = Directory(target);
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      for (final child in entity.listSync()) {
        await _copyEntity(
          child,
          '${targetDir.path}${Platform.pathSeparator}${_basename(child.path)}',
        );
      }
    }
  }

  static String _uniquePath(String path) {
    if (!File(path).existsSync() && !Directory(path).existsSync()) {
      return path;
    }
    final parent = File(path).parent.path;
    final base = _basename(path);
    final dot = base.lastIndexOf('.');
    final stem = dot <= 0 ? base : base.substring(0, dot);
    final ext = dot <= 0 ? '' : base.substring(dot);
    var index = 2;
    while (true) {
      final candidate = '$parent${Platform.pathSeparator}$stem-$index$ext';
      if (!File(candidate).existsSync() && !Directory(candidate).existsSync()) {
        return candidate;
      }
      index++;
    }
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', Platform.pathSeparator);
    final index = normalized.lastIndexOf(Platform.pathSeparator);
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  static bool _samePath(String a, String b) =>
      a.replaceAll('\\', '/').toLowerCase() ==
      b.replaceAll('\\', '/').toLowerCase();
}
