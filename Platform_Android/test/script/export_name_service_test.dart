import 'package:autoteleprompter/features/script/services/export_name_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExportNameService', () {
    test('keeps duplicate suffix before extension', () {
      final name = ExportNameService.nextDuplicateDisplayName(
        baseName: 'filename.rtf',
        format: 'rtf',
        existingDisplayNames: const ['filename.rtf'],
      );

      expect(name, 'filename (1).rtf');
      expect(name, isNot('filename.rtf (1)'));
    });

    test('increments duplicate suffix while preserving extension', () {
      final name = ExportNameService.nextDuplicateDisplayName(
        baseName: 'filename',
        format: 'rtf',
        existingDisplayNames: const [
          'filename.rtf',
          'filename (1).rtf',
          'filename (2).rtf',
        ],
      );

      expect(name, 'filename (3).rtf');
    });

    test('supports Hebrew filenames and unsafe characters', () {
      final name = ExportNameService.buildDisplayName(
        'דרשה: מבחן/שם.rtf',
        'rtf',
      );

      expect(name, 'דרשה_ מבחן_שם.rtf');
    });

    test('repairs Android broken duplicate suffix', () {
      final repaired = ExportNameService.repairBrokenDuplicateSuffix(
        'filename.rtf (1)',
        'rtf',
      );

      expect(repaired, 'filename (1).rtf');
    });

    test('validates expected extension', () {
      expect(
        ExportNameService.hasExpectedExtension('file (1).rtf', 'rtf'),
        isTrue,
      );
      expect(
        ExportNameService.hasExpectedExtension('file.rtf (1)', 'rtf'),
        isFalse,
      );
    });

    test('recognizes clean and broken duplicates for the same base', () {
      expect(
        ExportNameService.belongsToBaseName(
          displayName: 'filename.rtf',
          baseName: 'filename',
          format: 'rtf',
        ),
        isTrue,
      );
      expect(
        ExportNameService.belongsToBaseName(
          displayName: 'filename (1).rtf',
          baseName: 'filename.rtf',
          format: 'rtf',
        ),
        isTrue,
      );
      expect(
        ExportNameService.belongsToBaseName(
          displayName: 'filename.rtf (1)',
          baseName: 'filename',
          format: 'rtf',
        ),
        isTrue,
      );
      expect(
        ExportNameService.belongsToBaseName(
          displayName: 'filename-other.rtf',
          baseName: 'filename',
          format: 'rtf',
        ),
        isFalse,
      );
    });

    test('maps export formats to stable mime types', () {
      expect(ExportNameService.mimeTypeForFormat('rtf'), 'application/rtf');
      expect(
        ExportNameService.mimeTypeForFormat('docx'),
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      expect(ExportNameService.mimeTypeForFormat('txt'), 'text/plain');
    });
  });
}
