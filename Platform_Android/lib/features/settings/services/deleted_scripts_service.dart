import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../feedback/services/lightweight_diagnostics.dart';
import 'cloud_connection_store.dart';
import 'local_backup_service.dart';

class DeletedScriptEntry {
  final String path;
  final String name;
  final String originalName;
  final DateTime deletedAt;

  const DeletedScriptEntry({
    required this.path,
    required this.name,
    required this.originalName,
    required this.deletedAt,
  });

  String get displayName => originalName.trim().isEmpty ? name : originalName;

  DateTime get expiresAt => deletedAt.add(LocalBackupService.deletedRetention);

  int get daysRemaining {
    final remaining = expiresAt.difference(DateTime.now()).inDays;
    return remaining < 0 ? 0 : remaining + 1;
  }
}

class DeletedScriptRestoreResult {
  final File file;
  final String title;
  final String text;
  final String sourceType;
  final String sourcePath;
  final String cloudFileName;
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

  const DeletedScriptRestoreResult({
    required this.file,
    required this.title,
    required this.text,
    required this.sourceType,
    required this.sourcePath,
    required this.cloudFileName,
    this.historyJson,
    this.historyIndex,
    this.fontSize,
    this.fontFamily,
    this.lineSpacing,
    this.letterSpacing,
    this.wordSpacing,
    this.textAlign,
    this.scriptBgColor,
    this.currentWordColor,
    this.futureWordColor,
    this.isRtl,
  });
}

class DeletedScriptsService {
  static const _historyFolderName = 'local_backup_history';
  static final RegExp _deletedStampRe = RegExp(r'^(\d{8})_(\d{6})_');
  static final StreamController<void> _changes =
      StreamController<void>.broadcast();

  static Stream<void> get changes => _changes.stream;

  static void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  final CloudConnectionStore _store;

  DeletedScriptsService({CloudConnectionStore? store})
      : _store = store ?? CloudConnectionStore();

  Future<List<DeletedScriptEntry>> listLocalDeletedScripts() async {
    final folder = await _localDeletedFolder();
    if (folder == null || !await folder.exists()) return const [];
    await _pruneExpired(folder);

    final entries = <DeletedScriptEntry>[];
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      if (_basename(entity.path).toLowerCase().endsWith('.history.json')) {
        continue;
      }
      try {
        final stat = await entity.stat();
        entries.add(DeletedScriptEntry(
          path: entity.path,
          name: _basename(entity.path),
          originalName: _originalNameFromDeletedName(_basename(entity.path)),
          deletedAt:
              _deletedAtFromName(_basename(entity.path)) ?? stat.modified,
        ));
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'deletedScripts.listLocalEntry',
          data: {'path': entity.path},
        );
      }
    }
    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return entries;
  }

  Future<void> permanentlyDeleteLocal(DeletedScriptEntry entry) async {
    final file = File(entry.path);
    if (await file.exists()) {
      await file.delete();
    }
    final legacySidecar = File('${entry.path}.history.json');
    if (await legacySidecar.exists()) {
      await legacySidecar.delete();
    }
    final historyFile = await _historyMetadataFileForBackupPath(entry.path);
    if (historyFile != null && await historyFile.exists()) {
      await historyFile.delete();
    }
    notifyChanged();
  }

  Future<DeletedScriptRestoreResult?> restoreLocalDeletedScript(
    DeletedScriptEntry entry,
  ) async {
    final deletedFile = File(entry.path);
    if (!await deletedFile.exists()) return null;
    final metadata = await _readRestoreMetadata(entry.path);
    final target = await _restoreTargetFileFor(entry, metadata);
    await _moveFile(deletedFile, target);
    await _moveLegacySidecar(entry.path, target.path);
    await _moveHistoryMetadataRecord(
      oldBackupPath: entry.path,
      newBackupPath: target.path,
      scriptTitle: entry.displayName,
    );
    notifyChanged();
    final style = metadata['style'] is Map
        ? Map<String, dynamic>.from(metadata['style'] as Map)
        : const <String, dynamic>{};
    final text = metadata['rawText']?.toString().trim().isNotEmpty == true
        ? metadata['rawText'].toString()
        : await _readRestoredText(target);
    final sourceType =
        metadata['sourceType']?.toString().trim().isNotEmpty == true
            ? metadata['sourceType'].toString()
            : _sourceTypeFromFileName(target.path);
    return DeletedScriptRestoreResult(
      file: target,
      title: _basename(target.path),
      text: text,
      sourceType: sourceType,
      sourcePath: target.path,
      cloudFileName: entry.displayName,
      historyJson: metadata['historyJson']?.toString(),
      historyIndex: (metadata['historyIndex'] as num?)?.toInt(),
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
    );
  }

  Future<File> _restoreTargetFileFor(
    DeletedScriptEntry entry,
    Map<String, dynamic> metadata,
  ) async {
    final originalPath = metadata['sourcePath']?.toString().trim() ?? '';
    if (originalPath.isNotEmpty) {
      final original = File(originalPath);
      if (await original.parent.exists()) {
        return _uniqueRestoreFile(original.parent, _basename(original.path));
      }
    }
    final targetFolder = await _restoreTargetFolderFor(entry);
    await targetFolder.create(recursive: true);
    return _uniqueRestoreFile(targetFolder, entry.displayName);
  }

  Future<Directory> _restoreTargetFolderFor(DeletedScriptEntry entry) async {
    final backup = await _store.loadLocalBackupConnection();
    final backupPath = backup.folderPath.trim();
    if (backupPath.isNotEmpty) return Directory(backupPath);
    final deletedFolder = File(entry.path).parent;
    if (_basename(deletedFolder.path).toLowerCase() ==
        CloudConnectionStore.deletedScriptsFolderName.toLowerCase()) {
      return deletedFolder.parent;
    }
    return deletedFolder.parent;
  }

  Future<Map<String, dynamic>> _readRestoreMetadata(
    String backupFilePath,
  ) async {
    final file = await _historyMetadataFileForBackupPath(backupFilePath);
    if (file == null || !await file.exists()) return const {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'deletedScripts.readRestoreMetadata',
        data: {'path': backupFilePath},
      );
    }
    return const {};
  }

  Future<Directory?> _localDeletedFolder() async {
    final folderPath = await _store.resolveDeletedScriptsFolderPath();
    if (folderPath.trim().isEmpty) return null;
    return Directory(folderPath);
  }

  Future<void> _pruneExpired(Directory folder) async {
    final cutoff = DateTime.now().subtract(LocalBackupService.deletedRetention);
    await for (final entity in folder.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        final deletedAt =
            _deletedAtFromName(_basename(entity.path)) ?? stat.modified;
        if (!deletedAt.isBefore(cutoff)) continue;
        await permanentlyDeleteLocal(DeletedScriptEntry(
          path: entity.path,
          name: _basename(entity.path),
          originalName: _originalNameFromDeletedName(_basename(entity.path)),
          deletedAt: deletedAt,
        ));
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'deletedScripts.pruneExpired',
          data: {'path': entity.path},
        );
      }
    }
  }

  Future<File?> _historyMetadataFileForBackupPath(
    String backupFilePath, {
    bool create = false,
  }) async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(_join(support.path, _historyFolderName));
    if (!await folder.exists()) {
      if (!create) return null;
      await folder.create(recursive: true);
    }
    final id = sha256
        .convert(utf8.encode(File(backupFilePath).absolute.path.toLowerCase()))
        .toString();
    return File(_join(folder.path, '$id.history.json'));
  }

  Future<void> _moveLegacySidecar(
    String oldBackupPath,
    String newBackupPath,
  ) async {
    final oldSidecar = File('$oldBackupPath.history.json');
    if (!await oldSidecar.exists()) return;
    final newSidecar = File('$newBackupPath.history.json');
    if (await newSidecar.exists()) await newSidecar.delete();
    await _moveFile(oldSidecar, newSidecar);
  }

  Future<void> _moveHistoryMetadataRecord({
    required String oldBackupPath,
    required String newBackupPath,
    required String scriptTitle,
  }) async {
    final oldFile = await _historyMetadataFileForBackupPath(oldBackupPath);
    if (oldFile == null || !await oldFile.exists()) return;
    final decoded = jsonDecode(await oldFile.readAsString());
    final payload = decoded is Map<String, dynamic>
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    final historyJson = payload['historyJson']?.toString() ?? '';
    await oldFile.delete();
    if (payload.isEmpty && historyJson.trim().isEmpty) return;
    final newFile = await _historyMetadataFileForBackupPath(
      newBackupPath,
      create: true,
    );
    if (newFile == null) return;
    await newFile.writeAsString(jsonEncode({
      ...payload,
      'backupFilePath': newBackupPath,
      'backupFileName': _basename(newBackupPath),
      'scriptTitle': scriptTitle,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (historyJson.trim().isNotEmpty) 'historyJson': historyJson,
    }));
  }

  Future<String> _readRestoredText(File file) async {
    final lower = file.path.toLowerCase();
    try {
      final bytes = await file.readAsBytes();
      if (lower.endsWith('.txt') ||
          lower.endsWith('.text') ||
          lower.endsWith('.log') ||
          lower.endsWith('.md')) {
        return utf8.decode(bytes, allowMalformed: true).trim();
      }
      if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
        final raw = latin1.decode(bytes, allowInvalid: true);
        return _plainTextFromRtf(raw).trim();
      }
      return utf8.decode(bytes, allowMalformed: true).trim();
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'deletedScripts.readRestoredText',
        data: {'path': file.path},
      );
      return '';
    }
  }

  String _plainTextFromRtf(String raw) {
    final decoded = raw.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)));
    return decoded
        .replaceAll(RegExp(r'\\par[d]?'), '\n')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  String _sourceTypeFromFileName(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return 'DOCX';
    if (lower.endsWith('.rtf')) return 'RTF';
    if (lower.endsWith('.md')) return 'MD';
    if (lower.endsWith('.txt') || lower.endsWith('.text')) return 'TXT';
    return 'FILE';
  }

  Future<File> _uniqueRestoreFile(Directory folder, String fileName) async {
    final safeName = fileName.trim().isEmpty ? 'Restored script.txt' : fileName;
    final candidate = File(_join(folder.path, safeName));
    if (await candidate.exists()) {
      await candidate.delete();
    }
    return candidate;
  }

  Future<void> _moveFile(File source, File target) async {
    await target.parent.create(recursive: true);
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }

  static String _join(String left, String right) {
    final separator = Platform.pathSeparator;
    if (left.endsWith(separator)) return '$left$right';
    return '$left$separator$right';
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  static DateTime? _deletedAtFromName(String name) {
    final match = _deletedStampRe.firstMatch(name);
    if (match == null) return null;
    final date = match.group(1)!;
    final time = match.group(2)!;
    try {
      return DateTime(
        int.parse(date.substring(0, 4)),
        int.parse(date.substring(4, 6)),
        int.parse(date.substring(6, 8)),
        int.parse(time.substring(0, 2)),
        int.parse(time.substring(2, 4)),
        int.parse(time.substring(4, 6)),
      );
    } catch (_) {
      return null;
    }
  }

  static String _originalNameFromDeletedName(String name) {
    return name.replaceFirst(_deletedStampRe, '');
  }
}
