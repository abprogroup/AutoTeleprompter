import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/services/docx_service.dart';
import '../../script/services/markup_export_service.dart';
import '../../script/services/pages_service.dart';
import '../../script/services/rtf_service.dart';
import '../../script/services/script_bookmark_service.dart';
import 'cloud_connection_store.dart';

part 'local_backup_service.export_defaults.dart';
part 'local_backup_service.deleted.dart';
part 'local_backup_service.export_validation.dart';

class ScriptBackupExport {
  final String fileName;
  final String mimeType;
  final List<int> bytes;
  final String readableText;
  final String extension;
  final bool originalSourceCopy;

  const ScriptBackupExport({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.readableText,
    required this.extension,
    this.originalSourceCopy = false,
  });
}

/// Ported from Windows' `local_backup_service.dart`. Two formats Windows
/// supports are intentionally NOT ported here (Amit's explicit scope call):
/// PDF and ODT export require building `PdfExportService`/`OdtService` from
/// scratch on Android, which don't exist yet. RTF/DOCX/Pages export also
/// carry no explicit RTL styling here (unlike Windows) because Android's
/// `MarkupExportService` has no per-paragraph direction tracking at all -
/// that is a pre-existing, broader gap in Android's export pipeline, not
/// something introduced by this port. See `android_parity_gaps.md` #4.
class LocalBackupService {
  static const Duration deletedRetention = Duration(days: 30);
  static final RegExp _residualMarkupTagRe = RegExp(
    r'\[(?:/?(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|center|left|right|rtl|ltr|color|bg|size|font|align)'
    r'|(?:size|color|bg|font|align)(?:=[^\]]*)?'
    r'|(?:size|color|bg|font|align)/)\]',
    caseSensitive: false,
  );

  LocalBackupService({CloudConnectionStore? store})
      : _store = store ?? CloudConnectionStore();

  final CloudConnectionStore _store;

  Future<bool> backupScript({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? historyJson,
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    List<ScriptBookmark> bookmarks = const [],
  }) async {
    final root = await _backupRoot();
    final export = await buildScriptExportAsync(
      title: title,
      text: text,
      sourceType: sourceType,
      sourcePath: sourcePath,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
      bookmarks: bookmarks,
    );
    if (root == null || export.readableText.trim().isEmpty) return false;
    await _pruneExpiredDeletedBackups(root);
    final file = File(_join(root.path, export.fileName));
    await writeExportAtomically(file, export);
    await _storeHistoryMetadata(
      backupFile: file,
      scriptTitle: title,
      historyJson: historyJson,
    );
    await migrateHistorySidecarsFromBackupFolder();
    return true;
  }

  Future<void> migrateHistorySidecarsFromBackupFolder() async {
    final root = await _backupRoot();
    if (root == null) return;
    await _migrateHistorySidecars(root);
    await pruneOrphanHistoryMetadata();
  }

  Future<void> deleteBackupFileAndHistory(String backupFilePath) async {
    final file = File(backupFilePath);
    await deleteHistoryMetadataForBackupPath(backupFilePath);
    final legacySidecar = File('$backupFilePath.history.json');
    if (await legacySidecar.exists()) await legacySidecar.delete();
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteHistoryMetadataForBackupPath(String backupFilePath) async {
    final file = await _historyMetadataFileForBackupPath(backupFilePath);
    if (await file.exists()) await file.delete();
  }

  Future<void> pruneOrphanHistoryMetadata() async {
    final folder = await _historyMetadataFolder(create: false);
    if (folder == null || !await folder.exists()) return;
    try {
      await for (final entity in folder.list()) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.history.json')) continue;
        final decoded = jsonDecode(await entity.readAsString());
        final backupPath = decoded is Map<String, dynamic>
            ? decoded['backupFilePath']?.toString() ?? ''
            : '';
        if (backupPath.isEmpty || !await File(backupPath).exists()) {
          await entity.delete();
        }
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'localBackup.pruneHistoryMetadata',
      );
    }
  }

  Future<Directory?> _backupRoot() async {
    final connection = await _store.loadLocalBackupConnection();
    final folderPath = connection.folderPath.trim();
    if (folderPath.isEmpty) return null;
    final root = Directory(folderPath);
    await root.create(recursive: true);
    return root;
  }

  Future<Directory?> _deletedRoot() async {
    final folderPath = await _store.resolveDeletedScriptsFolderPath();
    if (folderPath.trim().isEmpty) return null;
    final root = Directory(folderPath);
    await root.create(recursive: true);
    return root;
  }

  Future<void> _pruneExpiredDeletedBackups(Directory root) async {
    final cutoff = DateTime.now().subtract(deletedRetention);
    for (final folderName in ['Deleted Scripts']) {
      final folder = Directory(_join(root.path, folderName));
      if (!await folder.exists()) continue;
      await for (final entity in folder.list(recursive: true)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (error, stack) {
          LightweightDiagnostics.instance.recordError(
            error,
            stack,
            source: 'localBackup.pruneDeleted',
          );
        }
      }
    }
  }

  Future<void> _pruneExpiredFolder(Directory folder) async {
    final cutoff = DateTime.now().subtract(deletedRetention);
    if (!await folder.exists()) return;
    await for (final entity in folder.list(recursive: true)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      } catch (error, stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'localBackup.pruneDeletedFolder',
        );
      }
    }
  }

  Future<void> _migrateHistorySidecars(Directory root) async {
    try {
      await for (final entity in root.list()) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.history.json')) continue;
        final backupPath = entity.path
            .substring(0, entity.path.length - '.history.json'.length);
        final historyJson = await entity.readAsString();
        if (historyJson.trim().isNotEmpty) {
          await _writeHistoryMetadataRecord(
            backupFilePath: backupPath,
            scriptTitle: _basename(backupPath),
            historyJson: historyJson,
          );
        }
        await entity.delete();
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'localBackup.migrateHistorySidecars',
      );
    }
  }

  Future<void> _storeHistoryMetadata({
    required File backupFile,
    required String scriptTitle,
    String? historyJson,
  }) async {
    final sidecar = File('${backupFile.path}.history.json');
    final sidecarHistory =
        await sidecar.exists() ? await sidecar.readAsString() : null;
    final history = (historyJson?.trim().isNotEmpty ?? false)
        ? historyJson!
        : sidecarHistory;
    if (history != null && history.trim().isNotEmpty) {
      await _writeHistoryMetadataRecord(
        backupFilePath: backupFile.path,
        scriptTitle: scriptTitle,
        historyJson: history,
      );
    }
    if (await sidecar.exists()) await sidecar.delete();
  }

  Future<void> _writeHistoryMetadataRecord({
    required String backupFilePath,
    required String scriptTitle,
    required String historyJson,
  }) async {
    final file = await _historyMetadataFileForBackupPath(backupFilePath);
    final payload = jsonEncode({
      'backupFilePath': backupFilePath,
      'backupFileName': _basename(backupFilePath),
      'scriptTitle': scriptTitle,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'historyJson': historyJson,
    });
    await _writeTextAtomically(file, payload);
  }

  Future<File> _historyMetadataFileForBackupPath(String backupFilePath) async {
    final folder = await _historyMetadataFolder(create: true);
    final id = sha256
        .convert(utf8.encode(File(backupFilePath).absolute.path.toLowerCase()))
        .toString();
    return File(_join(folder!.path, '$id.history.json'));
  }

  Future<Directory?> _historyMetadataFolder({required bool create}) async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(_join(support.path, 'local_backup_history'));
    if (create) await folder.create(recursive: true);
    return folder;
  }

  Future<void> _writeTextAtomically(File file, String text) async {
    await _writeBytesAtomically(file, utf8.encode(text));
  }

  static void validateExport(ScriptBackupExport export) =>
      _validateScriptExport(export);

  static Future<void> writeExportAtomically(
    File file,
    ScriptBackupExport export,
  ) async {
    _validateScriptExport(export);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.replace_backup');
    try {
      if (await temp.exists()) await temp.delete();
      if (await backup.exists()) await backup.delete();
      await temp.writeAsBytes(export.bytes, flush: true);
      _validateScriptExport(export);
      if (await file.exists()) {
        await file.rename(backup.path);
      }
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      if (await temp.exists()) await temp.delete();
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      } else if (await backup.exists()) {
        await backup.delete();
      }
      throw StateError('Could not save ${export.fileName}: $error');
    }
  }

  Future<void> _writeBytesAtomically(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  static String exportReadableScriptText(
    String text, {
    List<ScriptBookmark> bookmarks = const [],
  }) {
    if (text.trim().isEmpty) return '';
    final exportText = _textWithBookmarkSigns(text, bookmarks);
    final plain = MarkupExportService.toPlainText(exportText)
        .replaceAll(_residualMarkupTagRe, '')
        .replaceAll('**', '');
    return plain
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+$'), ''))
        .join('\n')
        .replaceAll(RegExp(r'\n{4,}'), '\n\n\n')
        .trimRight();
  }

  static ScriptBackupExport buildScriptExport({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? preferredExtension,
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    List<ScriptBookmark> bookmarks = const [],
  }) {
    final resolvedRtl = _resolveExportRtl(text, isRtl);
    final styledText = _applyExportDefaults(
      text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      futureWordColor: futureWordColor,
      isRtl: resolvedRtl,
    );
    final exportText = _textWithBookmarkSigns(styledText, bookmarks);
    final readableText = exportReadableScriptText(
      exportText,
      bookmarks: const [],
    );
    final baseName = _safeBaseName(
      title: title,
      sourcePath: sourcePath,
    );
    final extension = _preferredExtension(
      title: title,
      sourceType: sourceType,
      sourcePath: sourcePath,
      preferredExtension: preferredExtension,
    );

    switch (extension) {
      case 'rtf':
        return ScriptBackupExport(
          fileName: '$baseName.rtf',
          mimeType: 'application/rtf',
          bytes: RtfService.generate(exportText),
          readableText: readableText,
          extension: extension,
        );
      case 'docx':
        return ScriptBackupExport(
          fileName: '$baseName.docx',
          mimeType:
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          bytes: DocxService.generate(exportText),
          readableText: readableText,
          extension: extension,
        );
      case 'doc':
        return ScriptBackupExport(
          fileName: '$baseName.doc',
          mimeType: 'application/msword',
          bytes: RtfService.generate(exportText),
          readableText: readableText,
          extension: extension,
        );
      case 'pages':
        return ScriptBackupExport(
          fileName: '$baseName.pages',
          mimeType: _mimeTypeForExtension(extension),
          bytes: PagesService.generate(exportText),
          readableText: readableText,
          extension: extension,
        );
      case 'txt':
      case 'text':
      case 'log':
        return ScriptBackupExport(
          fileName: '$baseName.$extension',
          mimeType: _mimeTypeForExtension(extension),
          bytes: utf8.encode(readableText),
          readableText: readableText,
          extension: extension,
        );
      case 'md':
        return ScriptBackupExport(
          fileName: '$baseName.$extension',
          mimeType: _mimeTypeForExtension(extension),
          bytes: utf8.encode(readableText),
          readableText: readableText,
          extension: extension,
        );
      default:
        return ScriptBackupExport(
          fileName: '$baseName.txt',
          mimeType: 'text/plain; charset=utf-8',
          bytes: utf8.encode(readableText),
          readableText: readableText,
          extension: 'txt',
        );
    }
  }

  static Future<ScriptBackupExport> buildScriptExportAsync({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
    String? preferredExtension,
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    List<ScriptBookmark> bookmarks = const [],
  }) async {
    return buildScriptExport(
      title: title,
      text: text,
      sourceType: sourceType,
      sourcePath: sourcePath,
      preferredExtension: preferredExtension,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
      bookmarks: bookmarks,
    );
  }

  static String _preferredExtension({
    required String title,
    String? sourceType,
    String? sourcePath,
    String? preferredExtension,
  }) {
    final preferred = preferredExtension
        ?.trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^\.'), '');
    const supported = [
      'docx',
      'doc',
      'rtf',
      'txt',
      'text',
      'log',
      'md',
      'pages',
    ];
    if (preferred != null && supported.contains(preferred)) {
      return preferred;
    }
    final candidates = [
      sourcePath?.trim(),
      title.trim(),
      sourceType?.trim().toLowerCase(),
    ];
    for (final value in candidates) {
      if (value == null || value.isEmpty) continue;
      final lower = _stripAppExportSuffixes(value.toLowerCase());
      for (final ext in supported) {
        if (lower == ext || lower.endsWith('.$ext')) return ext;
      }
    }
    return 'txt';
  }

  static String _safeBaseName({
    required String title,
    String? sourcePath,
  }) {
    final rawName = (sourcePath?.trim().isNotEmpty ?? false)
        ? _basename(sourcePath!.trim())
        : title.trim();
    final withoutKnownExtension = _stripAppExportSuffixes(rawName).replaceFirst(
      RegExp(
        r'\.(?:docx?|rtf|txt|text|log|md|pages)$',
        caseSensitive: false,
      ),
      '',
    );
    final safe = _safeName(withoutKnownExtension);
    return safe.isEmpty ? 'Untitled script' : safe;
  }

  static String _stripAppExportSuffixes(String value) {
    var result = value.trim();
    var changed = true;
    while (changed) {
      changed = false;
      final next = result.replaceFirst(
        RegExp(r'\.(?:atp|atp\.txt)$', caseSensitive: false),
        '',
      );
      if (next != result) {
        result = next;
        changed = true;
      }
    }
    return result;
  }

  static String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _mimeTypeForExtension(String extension) {
    return switch (extension) {
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'doc' => 'application/msword',
      'rtf' => 'application/rtf',
      'md' => 'text/markdown; charset=utf-8',
      'pages' => 'application/octet-stream',
      _ => 'text/plain; charset=utf-8',
    };
  }

  static String _textWithBookmarkSigns(
    String text,
    List<ScriptBookmark> bookmarks,
  ) {
    if (bookmarks.isEmpty || text.trim().isEmpty) return text;
    const sign = '»';
    final blocks = text
        .replaceAll('Â»', sign)
        .split('\n')
        .map((block) => block.replaceAll(sign, ''))
        .toList();
    final grouped = <int, List<ScriptBookmark>>{};
    for (final bookmark in bookmarks) {
      if (bookmark.blockIndex < 0 || bookmark.blockIndex >= blocks.length) {
        continue;
      }
      grouped.putIfAbsent(bookmark.blockIndex, () => []).add(bookmark);
    }
    for (final entry in grouped.entries) {
      final ordered = [...entry.value]
        ..sort((a, b) => a.offset.compareTo(b.offset));
      var block = blocks[entry.key];
      for (final bookmark in ordered) {
        final offset = bookmark.offset.clamp(0, block.length).toInt();
        block = '${block.substring(0, offset)}$sign${block.substring(offset)}';
      }
      blocks[entry.key] = block;
    }
    return blocks.join('\n');
  }

  static String _safeName(String value) {
    final safe = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return safe.isEmpty ? 'script' : safe;
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
