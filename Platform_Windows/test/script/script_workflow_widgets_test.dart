import 'package:autoteleprompter/features/script/services/script_folder_import_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/suites/project_actions_mvp.dart';
import 'package:autoteleprompter/features/script/widgets/script_folder_import_dialog.dart';
import 'package:autoteleprompter/features/script/widgets/script_name_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('toolbar remains readable without overflow in a narrow window', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: AppBar(
      toolbarHeight: 132, automaticallyImplyLeading: false,
      title: ProjectActionsSuite(title: 'A long script name that should truncate',
        sourcePath: r'C:\Scripts\Opening.docx', onBack: () {}, onPresent: () {},
        onClear: () {}, onSave: () {}, onImport: () {}, onRename: () {}),
    ))));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Opening.docx'), findsOneWidget);
  });
  testWidgets('editor actions show script name, file purpose and app library', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectActionsSuite(
            title: 'Example script',
            onBack: () {},
            onPresent: () {},
            onClear: () {},
            onSave: () {},
            onImport: () {},
            onRename: () {},
          ),
        ),
      ),
    );
    expect(find.text('Script name'), findsOneWidget);
    expect(find.byTooltip('Rename script'), findsOneWidget);
    expect(find.byTooltip('Export file'), findsOneWidget);
    expect(find.byTooltip('Open script file'), findsOneWidget);
    expect(find.textContaining('App library'), findsOneWidget);
  });

  testWidgets(
    'new script rejects blank/duplicate names and explains no folder needed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptNameDialog(nameAlreadyUsed: (name) => name == 'Taken'),
          ),
        ),
      );
      expect(find.textContaining('No folder is needed'), findsOneWidget);
      await tester.tap(find.text('Create script'));
      await tester.pump();
      expect(find.text('Enter a script name.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Taken');
      await tester.tap(find.text('Create script'));
      await tester.pump();
      expect(find.textContaining('already in the app library'), findsOneWidget);
    },
  );

  testWidgets(
    'folder preview needs explicit import and skips duplicate names',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptFolderImportDialog(
              folderPath: r'C:\Scripts',
              preview: const FolderScriptPreview(
                [
                  FolderScriptFile(r'C:\Scripts\One.txt', 'One.txt', 'txt'),
                  FolderScriptFile(r'C:\Scripts\Two.txt', 'Two.txt', 'txt'),
                ],
                1,
                2,
                false,
              ),
              isDuplicate: (file) => file.name == 'One.txt',
              parse: (_) async => const FolderScriptContent('text'),
              save: (_, _) async {
                writes++;
                return true;
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('Originals stay unchanged'), findsOneWidget);
      expect(find.text('Already in app library — skipped'), findsOneWidget);
    expect(find.text('Import 1 script'), findsOneWidget);
      expect(writes, 0);
      final boxes = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(boxes.first.onChanged, isNull);
      expect(boxes.last.value, isTrue);
    },
  );
}
