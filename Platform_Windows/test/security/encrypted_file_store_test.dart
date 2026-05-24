import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/core/security/encrypted_file_store.dart';
import 'package:autoteleprompter/core/security/protected_data_service.dart';
import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encrypted file envelope round-trips without plaintext', () {
    final store = EncryptedFileStore(
      protectedData: const TestProtectedDataService(),
    );
    const phrase = 'DO_NOT_STORE_PLAINTEXT_SCRIPT';

    final envelope = store.protectToEnvelope(
      utf8.encode(phrase),
      kind: 'unit-test',
    );

    expect(envelope, isNot(contains(phrase)));
    final decrypted =
        store.unprotectEnvelope(envelope, expectedKind: 'unit-test');
    expect(utf8.decode(decrypted), phrase);
  });

  test('secure script store migrates metadata and removes full text', () async {
    final temp = await Directory.systemTemp.createTemp('secure_script_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final fileStore = EncryptedFileStore(
      protectedData: const TestProtectedDataService(),
      baseDirectory: () async => temp,
    );
    final store = SecureScriptStore(fileStore: fileStore);
    const phrase = 'SECRET_HEBREW_SCRIPT_MARKER';

    final migrated = await store.migrateRecentMetadata([
      jsonEncode({
        'title': 'Secret',
        'sessionId': 'session-1',
        'fullText': phrase,
        'historyJson': '[{"text":"$phrase"}]',
        'snippet': phrase,
      }),
    ]);

    final meta = jsonDecode(migrated.single) as Map<String, dynamic>;
    expect(meta.containsKey('fullText'), isFalse);
    expect(meta.containsKey('historyJson'), isFalse);
    expect(meta.containsKey('snippet'), isFalse);
    expect(meta[SecureScriptStore.recordIdKey], 'session-1');

    final files = temp.listSync(recursive: true).whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(await file.readAsString(), isNot(contains(phrase)));
    }

    final data = await store.readFromMetadata(meta);
    expect(data?.text, phrase);
    expect(data?.historyJson, contains(phrase));
  });

  test('last script migration preserves existing encrypted history', () async {
    final temp =
        await Directory.systemTemp.createTemp('secure_script_history_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final store = SecureScriptStore(
      fileStore: EncryptedFileStore(
        protectedData: const TestProtectedDataService(),
        baseDirectory: () async => temp,
      ),
    );

    const phrase = 'HISTORY_MUST_SURVIVE_MIGRATION';
    await store.save(
      recordId: 'session-1',
      text: phrase,
      historyJson: '[{"text":"$phrase"}]',
    );

    final migratedId = await store.migrateLastScript(
      lastScript: phrase,
      lastTitle: 'Secret',
      fallbackSessionId: 'session-1',
    );

    expect(migratedId, 'session-1');
    final data = await store.read('session-1');
    expect(data?.text, phrase);
    expect(data?.historyJson, contains(phrase));
  });
}
