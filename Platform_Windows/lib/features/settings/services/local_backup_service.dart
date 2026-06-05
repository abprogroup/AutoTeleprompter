import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/services/docx_service.dart';
import '../../script/services/markup_export_service.dart';
import '../../script/services/odt_service.dart';
import '../../script/services/pages_service.dart';
import '../../script/services/pdf_export_service.dart';
import '../../script/services/rtf_service.dart';
import '../../script/services/script_bookmark_service.dart';
import 'cloud_connection_store.dart';

part 'local_backup_service.export_defaults.dart';

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
    await _writeBytesAtomically(file, export.bytes);
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

  Future<bool> backupDeletedScript({
    required String title,
    required String text,
    String? sourceType,
    String? sourcePath,
  }) async {
    final root = await _backupRoot();
    if (root == null) return false;
    await _pruneExpiredDeletedBackups(root);
    final stamp = _timestamp();
    var backedUp = false;

    final movedExisting = await _moveExistingBackupToDeleted(
      root: root,
      title: title,
      text: text,
      sourceType: sourceType,
      sourcePath: sourcePath,
      stamp: stamp,
    );
    if (movedExisting) backedUp = true;

    final readableText = exportReadableScriptText(text);
    if (!movedExisting && readableText.trim().isNotEmpty) {
      final deleted = Directory(_join(root.path, 'Deleted Scripts'));
      await deleted.create(recursive: true);
      final export = await _deletedScriptExport(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
      );
      await _writeBytesAtomically(
        File(_join(deleted.path, '${stamp}_${export.fileName}')),
        export.bytes,
      );
      backedUp = true;
    }

    final rawSourcePath = sourcePath?.trim() ?? '';
    final source = rawSourcePath.isEmpty ? null : File(rawSourcePath);
    if (source != null && await source.exists()) {
      final originals = Directory(_join(root.path, 'Deleted Source Files'));
      await originals.create(recursive: true);
      final originalName = _safeName(_basename(source.path));
      final target = File(_join(originals.path, '${stamp}_$originalName'));
      await source.copy(target.path);
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
      return await buildScriptExportAsync(
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
      final readableText = exportReadableScriptText(text);
      final baseName = _safeBaseName(title: title, sourcePath: sourcePath);
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
    required String title,
    required String text,
    required String stamp,
    String? sourceType,
    String? sourcePath,
  }) async {
    try {
      final export = await buildScriptExportAsync(
        title: title,
        text: text,
        sourceType: sourceType,
        sourcePath: sourcePath,
      );
      final candidateNames = <String>{
        export.fileName,
        _safeName(_basename(sourcePath?.trim() ?? '')),
      }..removeWhere((name) => name.trim().isEmpty || name == 'script');

      File? sourceBackup;
      for (final name in candidateNames) {
        final candidate = File(_join(root.path, name));
        if (await candidate.exists()) {
          sourceBackup = candidate;
          break;
        }
      }
      if (sourceBackup == null) return false;

      final deleted = Directory(_join(root.path, 'Deleted Scripts'));
      await deleted.create(recursive: true);
      final target = await _uniqueFile(
        Directory(deleted.path),
        '${stamp}_${_basename(sourceBackup.path)}',
      );
      await _moveFileAtomically(sourceBackup, target);
      await _moveHistoryMetadataRecord(
        oldBackupPath: sourceBackup.path,
        newBackupPath: target.path,
        scriptTitle: title,
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
    final safeName = _safeName(fileName);
    var candidate = File(_join(directory.path, safeName));
    if (!await candidate.exists()) return candidate;
    final dot = safeName.lastIndexOf('.');
    final base = dot <= 0 ? safeName : safeName.substring(0, dot);
    final ext = dot <= 0 ? '' : safeName.substring(dot);
    for (var i = 2; i < 1000; i++) {
      candidate = File(_join(directory.path, '$base ($i)$ext'));
      if (!await candidate.exists()) return candidate;
    }
    return File(_join(directory.path,
        '${base}_${DateTime.now().microsecondsSinceEpoch}$ext'));
  }

  Future<Directory?> _backupRoot() async {
    final connection = await _store.loadLocalBackupConnection();
    final folderPath = connection.folderPath.trim();
    if (folderPath.isEmpty) return null;
    final root = Directory(folderPath);
    await root.create(recursive: true);
    return root;
  }

  Future<void> _pruneExpiredDeletedBackups(Directory root) async {
    final cutoff = DateTime.now().subtract(deletedRetention);
    for (final folderName in ['Deleted Scripts', 'Deleted Source Files']) {
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
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    List<ScriptBookmark> bookmarks = const [],
  }) {
    final styledText = _applyExportDefaults(
      text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
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
      case 'odt':
        return ScriptBackupExport(
          fileName: '$baseName.odt',
          mimeType: _mimeTypeForExtension(extension),
          bytes: OdtService.generate(exportText),
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
      case 'md':
        return ScriptBackupExport(
          fileName: '$baseName.$extension',
          mimeType: _mimeTypeForExtension(extension),
          bytes: utf8.encode(readableText),
          readableText: readableText,
          extension: extension,
        );
      case 'pdf':
        throw StateError('PDF export requires buildScriptExportAsync.');
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
    double? fontSize,
    String? fontFamily,
    String? textAlign,
    int? futureWordColor,
    bool? isRtl,
    List<ScriptBookmark> bookmarks = const [],
  }) async {
    final extension = _preferredExtension(
      title: title,
      sourceType: sourceType,
      sourcePath: sourcePath,
    );
    if (extension != 'pdf') {
      return buildScriptExport(
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
    }

    final styledText = _applyExportDefaults(
      text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      futureWordColor: futureWordColor,
      isRtl: isRtl,
    );
    final exportText = _textWithBookmarkSigns(styledText, bookmarks);
    final readableText = exportReadableScriptText(exportText);
    final baseName = _safeBaseName(title: title, sourcePath: sourcePath);
    return ScriptBackupExport(
      fileName: '$baseName.pdf',
      mimeType: _mimeTypeForExtension('pdf'),
      bytes: await PdfExportService.generate(exportText),
      readableText: readableText,
      extension: 'pdf',
    );
  }

  static String _preferredExtension({
    required String title,
    String? sourceType,
    String? sourcePath,
  }) {
    final candidates = [
      sourcePath?.trim(),
      title.trim(),
      sourceType?.trim().toLowerCase(),
    ];
    for (final value in candidates) {
      if (value == null || value.isEmpty) continue;
      final lower = _stripAppExportSuffixes(value.toLowerCase());
      for (final ext in [
        'docx',
        'doc',
        'rtf',
        'txt',
        'text',
        'log',
        'md',
        'pdf',
        'odt',
        'pages',
      ]) {
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
        r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages)$',
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
      'pdf' => 'application/pdf',
      'odt' => 'application/vnd.oasis.opendocument.text',
      'pages' => 'application/octet-stream',
      _ => 'text/plain; charset=utf-8',
    };
  }

  static String _textWithBookmarkSigns(
    String text,
    List<ScriptBookmark> bookmarks,
  ) {
    if (bookmarks.isEmpty || text.trim().isEmpty) return text;
    const sign = '\u00BB';
    final blocks = text
        .replaceAll('\u00C2\u00BB', sign)
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
