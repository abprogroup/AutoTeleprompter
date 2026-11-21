import 'dart:io';
import 'package:autoteleprompter/features/script/services/script_folder_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('atp_folder_test_');
  });
  tearDown(() async {
    await folder.delete(recursive: true);
  });

  test(
    'flat preview exposes supported files only and leaves originals unchanged',
    () async {
      await File('${folder.path}/One.txt').writeAsString('Original one');
      await File('${folder.path}/Two.md').writeAsString('Original two');
      await File('${folder.path}/binary.pdf').writeAsBytes([0, 1, 2]);
      await Directory('${folder.path}/nested').create();
      await File(
        '${folder.path}/nested/Hidden.txt',
      ).writeAsString('do not import');
      final preview = await ScriptFolderImportService.scan(folder.path);
      expect(preview.files.map((e) => e.name).toSet(), {'One.txt', 'Two.md'});
      expect(preview.skippedFiles, 1);
      expect(preview.skippedFolders, 1);
      final saved = <String>[];
      final report = await ScriptFolderImportService.importSelected(
        preview.files,
        parse: (file) async => FolderScriptContent(await file.readAsString()),
        save: (file, parsed) async {
          saved.add(parsed.text);
          return true;
        },
        isCancelled: () => false,
      );
      expect(report.imported, 2);
      expect(saved.toSet(), {'Original one', 'Original two'});
      expect(
        await File('${folder.path}/One.txt').readAsString(),
        'Original one',
      );
      expect(
        await File('${folder.path}/Two.md').readAsString(),
        'Original two',
      );
      expect(await File('${folder.path}/binary.pdf').readAsBytes(), [0, 1, 2]);
    },
  );

  test(
    'cancel during parsing does not commit and duplicate skip is explicit',
    () async {
      await File('${folder.path}/One.txt').writeAsString('one');
      final preview = await ScriptFolderImportService.scan(folder.path);
      var cancelled = false;
      var writes = 0;
      final cancelledReport = await ScriptFolderImportService.importSelected(
        preview.files,
        parse: (file) async {
          cancelled = true;
          return const FolderScriptContent('one');
        },
        save: (file, parsed) async {
          writes++;
          return true;
        },
        isCancelled: () => cancelled,
      );
      expect(writes, 0);
      expect(cancelledReport.cancelled, isTrue);
      final duplicates = await ScriptFolderImportService.importSelected(
        preview.files,
        parse: (file) async => const FolderScriptContent('one'),
        save: (file, parsed) async => false,
        isCancelled: () => false,
      );
      expect(duplicates.imported, 0);
      expect(duplicates.skipped.single, contains('already in the app library'));
    },
  );

  test('file changed to a folder after preview fails safely', () async {
    final file = File('${folder.path}/One.txt');
    await file.writeAsString('one');
    final preview = await ScriptFolderImportService.scan(folder.path);
    await file.delete();
    await Directory(file.path).create();
    final report = await ScriptFolderImportService.importSelected(
      preview.files,
      parse: (_) async => throw StateError('must not parse'),
      save: (_, _) async => throw StateError('must not write'),
      isCancelled: () => false,
    );
    expect(report.imported, 0);
    expect(report.skipped.length, 1);
  });
}
