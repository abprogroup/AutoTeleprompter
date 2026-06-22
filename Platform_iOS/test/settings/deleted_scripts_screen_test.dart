import 'dart:io';

import 'package:autoteleprompter/features/settings/services/deleted_scripts_service.dart';
import 'package:autoteleprompter/features/settings/widgets/deleted_scripts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an error when deleted-script restore fails',
      (tester) async {
    final service = _FakeDeletedScriptsService(throwOnRestore: true);

    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Could not restore Old Script.txt.'), findsOneWidget);
  });

  testWidgets('shows an error when permanent delete fails', (tester) async {
    final service = _FakeDeletedScriptsService(throwOnDelete: true);

    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Could not delete Old Script.txt.'), findsOneWidget);
  });
}

Widget _host(DeletedScriptsService service) => ProviderScope(
      child: MaterialApp(
        home: DeletedScriptsScreen(service: service),
      ),
    );

class _FakeDeletedScriptsService extends DeletedScriptsService {
  _FakeDeletedScriptsService({
    this.throwOnRestore = false,
    this.throwOnDelete = false,
  });

  final bool throwOnRestore;
  final bool throwOnDelete;

  final _entry = DeletedScriptEntry(
    path: '/tmp/old-script.txt',
    name: 'Old Script.txt',
    originalName: 'Old Script.txt',
    deletedAt: DateTime.now(),
  );

  @override
  Future<List<DeletedScriptEntry>> listLocalDeletedScripts() async => [_entry];

  @override
  Future<DeletedScriptRestoreResult?> restoreLocalDeletedScript(
    DeletedScriptEntry entry,
  ) async {
    if (throwOnRestore) throw FileSystemException('blocked', entry.path);
    return DeletedScriptRestoreResult(
      file: File(entry.path),
      title: entry.displayName,
      text: 'Restored text',
      sourceType: 'TXT',
      sourcePath: entry.path,
      cloudFileName: entry.name,
    );
  }

  @override
  Future<void> permanentlyDeleteLocal(DeletedScriptEntry entry) async {
    if (throwOnDelete) throw FileSystemException('blocked', entry.path);
  }
}
