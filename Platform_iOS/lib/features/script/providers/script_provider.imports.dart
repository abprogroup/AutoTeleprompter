part of 'script_provider.dart';

extension ScriptProviderImportParsing on ScriptNotifier {
  Future<ParsedFile> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    ParsedFile result = ParsedFile('');

    try {
      final byteLength = await file.length();
      _validateImportFileSize(lower, byteLength);
      final rawBytes = await file.readAsBytes();
      if (lower.endsWith('.docx')) {
        result = _parseDocx(rawBytes);
      } else if (lower.endsWith('.pages')) {
        result = _parsePages(rawBytes);
      } else if (lower.endsWith('.rtf') || lower.endsWith('.doc')) {
        final rawRtf = latin1.decode(rawBytes);
        if (rawRtf.trimLeft().startsWith('{\\rtf')) {
          result = _parseRtf(rawRtf);
        } else if (lower.endsWith('.rtf')) {
          // Non-RTF content in a .rtf file: keep visible UTF-8 text intact.
          final raw = utf8.decode(rawBytes, allowMalformed: true);
          result = ParsedFile(raw);
        } else {
          // Legacy .doc binary files: strip non-printable bytes.
          final content = String.fromCharCodes(
            rawBytes.where(
              (b) => (b >= 0x20 && b < 0x7F) || b == 0x0A || b == 0x0D,
            ),
          ).replaceAll(RegExp(r'[ \t]{3,}'), '  ');
          result = ParsedFile(content);
        }
      } else {
        result = ParsedFile(utf8.decode(rawBytes, allowMalformed: true));
      }
    } catch (error, stack) {
      final errStr = error.toString();
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'iosImport.parseFile',
      );
      final errContent =
          errStr.contains('Central Directory') || errStr.contains('Format')
              ? 'This file appears to be corrupted or is not a valid '
                  '${file.path.split('.').last.toUpperCase()} file.'
              : 'Error loading file: $errStr';
      result = ParsedFile(errContent, errorMessage: errContent);
    }
    return result;
  }

  void _validateImportFileSize(String lowerPath, int byteLength) {
    final isArchive =
        lowerPath.endsWith('.docx') || lowerPath.endsWith('.pages');
    final maxBytes = isArchive ? _maxArchiveImportBytes : _maxPlainImportBytes;
    if (byteLength > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).round();
      throw ImportSafetyException(
        'This file is too large to import safely. '
        'The current limit for this format is ${mb}MB.',
      );
    }
  }

  Archive _decodeCheckedArchive(List<int> rawBytes, String format) {
    final archive = ZipDecoder().decodeBytes(rawBytes);
    if (archive.files.length > _maxArchiveEntries) {
      throw ImportSafetyException(
        '$format has too many internal files to import safely.',
      );
    }
    var expandedBytes = 0;
    for (final file in archive.files) {
      expandedBytes += file.size;
      if (expandedBytes > _maxArchiveExpandedBytes) {
        throw ImportSafetyException(
          '$format expands to too much data to import safely.',
        );
      }
    }
    return archive;
  }

  List<int> _archiveFileBytes(
    ArchiveFile file, {
    required String format,
    bool isXml = false,
  }) {
    final maxBytes = isXml ? _maxImportXmlBytes : _maxArchiveExpandedBytes;
    if (file.size > maxBytes) {
      throw ImportSafetyException(
        '$format contains an internal file that is too large to import safely.',
      );
    }
    final dynamic rawContent = file.content;
    final bytes = rawContent is List<int>
        ? rawContent
        : List<int>.from(rawContent as Iterable);
    if (bytes.length > maxBytes) {
      throw ImportSafetyException(
        '$format contains an internal file that is too large to import safely.',
      );
    }
    return bytes;
  }

  Future<void> importFile(File file) async {
    final settingsBeforeImport = ref.read(settingsProvider);
    final result = await parseFile(file);
    if (result.isError) return;
    if (result.text.isEmpty) return;
    final parsedSettings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    if (settingsBeforeImport.importColorMode ==
        AppSettings.importColorModeDocument) {
      final parsedBgChanged =
          parsedSettings.scriptBgColor != settingsBeforeImport.scriptBgColor;
      await settingsNotifier.setDocumentImportAppearance(
        scriptBgColor: parsedBgChanged ? parsedSettings.scriptBgColor : null,
      );
    } else {
      await settingsNotifier.resetToDefaultAppearance();
    }
    final title = file.path.split(RegExp(r'[\\/]')).last;
    final extension =
        title.contains('.') ? title.split('.').last.toUpperCase() : 'FILE';
    loadText(
      result.text,
      title: title,
      sourceType: extension,
      sourcePath: file.path,
      fontSize: result.fontSize,
    );
  }
}

class ImportSafetyException implements Exception {
  final String message;

  const ImportSafetyException(this.message);

  @override
  String toString() => message;
}
