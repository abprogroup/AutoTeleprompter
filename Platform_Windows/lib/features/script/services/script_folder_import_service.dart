import 'dart:io';

class FolderScriptFile {
  final String path;
  final String name;
  final String extension;
  const FolderScriptFile(this.path, this.name, this.extension);
}

class FolderScriptPreview {
  final List<FolderScriptFile> files;
  final int skippedFiles;
  final int skippedFolders;
  final bool truncated;
  const FolderScriptPreview(
    this.files,
    this.skippedFiles,
    this.skippedFolders,
    this.truncated,
  );
}

class FolderScriptContent {
  final String text;
  final Map<String, dynamic> style;
  const FolderScriptContent(this.text, {this.style = const {}});
}

class FolderScriptImportReport {
  final int imported;
  final List<String> skipped;
  final bool cancelled;
  const FolderScriptImportReport(this.imported, this.skipped, this.cancelled);
}

/// Copies parsed content into the library; never writes to the source directory.
/// Only formats with real parser paths are offered, not legacy picker fallbacks.
class ScriptFolderImportService {
  static const extensions = {'docx', 'doc', 'rtf', 'txt', 'md', 'log', 'text'};
  static const formatsLabel = 'DOCX, DOC, RTF, TXT, MD, LOG, TEXT';
  static const maxEntries = 500;

  static Future<FolderScriptPreview> scan(String folderPath) async {
    final files = <FolderScriptFile>[];
    var skipped = 0;
    var folders = 0;
    var inspected = 0;
    var truncated = false;
    await for (final entity in Directory(folderPath).list(followLinks: false)) {
      if (++inspected > maxEntries) {
        truncated = true;
        break;
      }
      if (entity is Directory) {
        folders++;
        continue;
      }
      final name = entity.path.split(RegExp(r'[/\\]')).last;
      final extension =
          name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (entity is! File || !extensions.contains(extension)) {
        skipped++;
        continue;
      }
      files.add(FolderScriptFile(entity.absolute.path, name, extension));
    }
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return FolderScriptPreview(
      List.unmodifiable(files),
      skipped,
      folders,
      truncated,
    );
  }

  static Future<FolderScriptImportReport> importSelected(
    List<FolderScriptFile> files, {
    required Future<FolderScriptContent> Function(File file) parse,
    required Future<bool> Function(
      FolderScriptFile file,
      FolderScriptContent content,
    ) save,
    required bool Function() isCancelled,
    void Function(int completed, int total)? onProgress,
  }) async {
    var imported = 0;
    final skipped = <String>[];
    for (var i = 0; i < files.length; i++) {
      if (isCancelled()) break;
      final candidate = files[i];
      try {
        if (!extensions.contains(candidate.extension) ||
            await FileSystemEntity.type(candidate.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw const FileSystemException(
            'File is no longer a regular supported file.',
          );
        }
        final parsed = await parse(File(candidate.path));
        if (isCancelled()) break;
        if (parsed.text.trim().isEmpty) {
          skipped.add('${candidate.name}: no readable script text.');
        } else if (await save(candidate, parsed)) {
          imported++;
        } else {
          skipped.add(
            '${candidate.name}: already in the app library (name or source file).',
          );
        }
      } catch (_) {
        skipped.add(
          '${candidate.name}: could not import this file; original unchanged.',
        );
      }
      onProgress?.call(i + 1, files.length);
    }
    return FolderScriptImportReport(
      imported,
      List.unmodifiable(skipped),
      isCancelled(),
    );
  }
}
