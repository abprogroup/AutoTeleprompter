import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/settings/services/cloud_connection_store.dart';
import 'package:autoteleprompter/features/settings/services/deleted_scripts_service.dart';
import 'package:autoteleprompter/features/settings/services/local_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory backupDir;
  late Directory supportDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backupDir = await Directory.systemTemp.createTemp('ios_local_backup_');
    supportDir = await Directory.systemTemp.createTemp('ios_backup_support_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return supportDir.path;
      }
      return null;
    });
  });

  tearDown(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await backupDir.exists()) await backupDir.delete(recursive: true);
    if (await supportDir.exists()) await supportDir.delete(recursive: true);
  });

  test('backupScript is a no-op until a local folder is connected', () async {
    final backedUp = await LocalBackupService().backupScript(
      title: 'No Folder',
      text: 'Hello backup',
      sourceType: 'TXT',
    );

    expect(backedUp, isFalse);
    expect(await backupDir.list().isEmpty, isTrue);
  });

  test('backupScript writes a markup-clean local export', () async {
    await CloudConnectionStore().setLocalBackupPath(backupDir.path);

    final backedUp = await LocalBackupService().backupScript(
      title: 'Styled Script.rtf',
      text: '[rtl][font=Roboto]שלום[/font] [yc]world[/yc][/rtl]',
      sourceType: 'RTF',
      fontFamily: 'Roboto',
      futureWordColor: 0xFFFFFFFF,
      isRtl: true,
    );

    expect(backedUp, isTrue);
    final files = <File>[];
    await for (final entity in backupDir.list()) {
      if (entity is File) files.add(entity);
    }
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('Styled Script.rtf'));
    final content = await files.single.readAsString();
    expect(content, startsWith(r'{\rtf1'));
    expect(content, isNot(contains('[font=')));
    expect(content, isNot(contains('[yc]')));
    expect(content, contains(r'\rtlpar'));
  });

  test('buildScriptExport preserves original source extension', () {
    final export = LocalBackupService.buildScriptExport(
      title: 'Imported Script',
      sourcePath: '/tmp/original.docx',
      text: '**Hello** [bg=#FFFF00]world[/bg]',
    );

    expect(export.fileName, 'original.docx');
    expect(export.extension, 'docx');
    expect(export.readableText, 'Hello world');
    expect(export.bytes, isNotEmpty);
  });

  test('saveScript snapshots normal saves to the connected local folder',
      () async {
    await CloudConnectionStore().setLocalBackupPath(backupDir.path);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).saveScript(
          'Hello [yc]backup[/yc]',
          title: 'Provider Save.txt',
          type: 'TXT',
          sessionId: 'provider-save',
        );

    final files = <File>[];
    await for (final entity in backupDir.list()) {
      if (entity is File) files.add(entity);
    }
    expect(files.map((file) => file.path),
        contains(endsWith('Provider Save.txt')));
    final saved = files.firstWhere((file) => file.path.endsWith('.txt'));
    expect(await saved.readAsString(), 'Hello backup');
  });

  test('removeFromRecent moves a backed-up script to Deleted Scripts',
      () async {
    await CloudConnectionStore().setLocalBackupPath(backupDir.path);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).saveScript(
          'Delete me [yc]cleanly[/yc]',
          title: 'Delete Me.txt',
          type: 'TXT',
          sessionId: 'delete-me',
        );
    await container.read(settingsProvider.notifier).removeFromRecent(
          'delete-me',
        );

    final deletedDir = Directory(
      '${backupDir.path}${Platform.pathSeparator}Deleted Scripts',
    );
    final deletedFiles = <File>[];
    await for (final entity in deletedDir.list()) {
      if (entity is File) deletedFiles.add(entity);
    }

    expect(deletedFiles, hasLength(1));
    expect(deletedFiles.single.path, contains('Delete Me.txt'));
    expect(await deletedFiles.single.readAsString(), 'Delete me cleanly');
  });

  test('DeletedScriptsService lists and restores local deleted backups',
      () async {
    await CloudConnectionStore().setLocalBackupPath(backupDir.path);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).saveScript(
          'Restore me',
          title: 'Restore Me.txt',
          type: 'TXT',
          sessionId: 'restore-me',
        );
    await container.read(settingsProvider.notifier).removeFromRecent(
          'restore-me',
        );

    final service = DeletedScriptsService();
    final entries = await service.listLocalDeletedScripts();
    expect(entries, hasLength(1));
    expect(entries.single.displayName, contains('Restore Me.txt'));

    final restored = await service.restoreLocalDeletedScript(entries.single);
    expect(restored, isNotNull);
    expect(restored!.text, 'Restore me');
    expect(restored.title, 'Restore Me.txt');
    expect(await File(restored.sourcePath).exists(), isTrue);
    expect(await service.listLocalDeletedScripts(), isEmpty);
  });
}
