import 'package:autoteleprompter/features/settings/services/cloud_connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalizes unsafe cloud paths', () {
    expect(
      CloudConnectionStore.normalizePath('  /tmp/Auto\nTeleprompter\r '),
      '/tmp/AutoTeleprompter',
    );
  });

  test('local backup path migrates legacy provider paths and disconnects them',
      () async {
    SharedPreferences.setMockInitialValues({
      'cloudFolder.google_drive': '/legacy/google',
    });
    final store = CloudConnectionStore();

    final migrated = await store.loadLocalBackupConnection();
    expect(migrated.folderPath, '/legacy/google');

    await store.setLocalBackupPath('/mobile/local');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cloudFolder.local_backup'), '/mobile/local');
    expect(prefs.getString('cloudFolder.google_drive'), isNull);

    await store.disconnectLocalBackup();
    expect(prefs.getString('cloudFolder.local_backup'), isNull);
  });

  test('deleted scripts folder resolves from custom path or local backup',
      () async {
    final store = CloudConnectionStore();
    await store.setLocalBackupPath('/mobile/backups');

    expect(
      await store.resolveDeletedScriptsFolderPath(),
      '/mobile/backups/Deleted Scripts',
    );

    await store.setDeletedScriptsCustomFolderEnabled(true);
    await store.setDeletedScriptsCustomFolderPath('/mobile/deleted');
    expect(await store.resolveDeletedScriptsFolderPath(), '/mobile/deleted');
  });
}
