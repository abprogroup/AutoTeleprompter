part of 'local_backup_service.dart';

void _validateScriptExport(ScriptBackupExport export) {
  if (export.bytes.isEmpty) {
    throw StateError('Export produced an empty ${export.extension} file.');
  }
  switch (export.extension.toLowerCase()) {
    case 'rtf':
    case 'doc':
      _validateRtfCompatibleExport(export);
      return;
    case 'docx':
      _validateZipExport(
        export,
        requiredEntries: const [
          '[Content_Types].xml',
          '_rels/.rels',
          'word/document.xml',
        ],
      );
      return;
    case 'txt':
    case 'text':
    case 'log':
    case 'md':
      utf8.decode(export.bytes, allowMalformed: false);
      return;
  }
}

void _validateRtfCompatibleExport(ScriptBackupExport export) {
  final prefix = ascii.decode(
    export.bytes.take(8).toList(),
    allowInvalid: true,
  );
  if (!prefix.startsWith(r'{\rtf1')) {
    throw StateError(
      '${export.extension.toUpperCase()} export is not RTF-compatible.',
    );
  }
}

void _validateZipExport(
  ScriptBackupExport export, {
  required List<String> requiredEntries,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(export.bytes);
  } catch (error) {
    throw StateError(
      '${export.extension.toUpperCase()} export is not a readable package: '
      '$error',
    );
  }
  final names = archive.files.map((file) => file.name).toSet();
  for (final entry in requiredEntries) {
    if (!names.contains(entry)) {
      throw StateError(
        '${export.extension.toUpperCase()} export is missing $entry.',
      );
    }
  }
}
