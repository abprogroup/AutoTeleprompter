import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:autoteleprompter/core/security/encrypted_file_store.dart';
import 'package:autoteleprompter/core/security/protected_data_service.dart';
import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('windows DPAPI protect/unprotect round-trips for current account', () {
    if (!Platform.isWindows) return;
    const service = DpapiProtectedDataService();
    final protected = service.protect(
      Uint8List.fromList(utf8.encode('DPAPI_CURRENT_USER_SMOKE')),
      kind: 'unit-test',
    );

    expect(protected, isNotEmpty);
    final unprotected = service.unprotect(
      protected,
      expectedKind: 'unit-test',
    );
    expect(utf8.decode(unprotected), 'DPAPI_CURRENT_USER_SMOKE');
  });

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

  test('failed recent migration never keeps plaintext script fields', () async {
    final store = SecureScriptStore(fileStore: ThrowingEncryptedFileStore());
    const phrase = 'PLAINTEXT_MUST_NOT_SURVIVE_FAILED_MIGRATION';
    final issues = <String>[];

    final migrated = await store.migrateRecentMetadata(
      [
        jsonEncode({
          'title': 'Unsafe',
          'sessionId': 'session-fail',
          'fullText': phrase,
          'historyJson': '[{"text":"$phrase"}]',
          'snippet': phrase,
        }),
      ],
      onIssue: (issue, error, stackTrace, index) {
        issues.add('$issue:$index');
      },
    );

    expect(migrated, hasLength(1));
    expect(issues, contains('secure-recent-migration-failed:0'));
    expect(migrated.single, isNot(contains(phrase)));
    final meta = jsonDecode(migrated.single) as Map<String, dynamic>;
    expect(meta['title'], 'Unsafe');
    expect(meta.containsKey('fullText'), isFalse);
    expect(meta.containsKey('historyJson'), isFalse);
    expect(meta.containsKey('snippet'), isFalse);
  });

  test('malformed recent migration reports scrub failure and drops entry',
      () async {
    final store = SecureScriptStore(
      fileStore: EncryptedFileStore(
        protectedData: const TestProtectedDataService(),
      ),
    );
    final issues = <String>[];

    final migrated = await store.migrateRecentMetadata(
      ['not-json'],
      onIssue: (issue, error, stackTrace, index) {
        issues.add('$issue:$index');
      },
    );

    expect(migrated, isEmpty);
    expect(issues, contains('secure-recent-migration-failed:0'));
    expect(issues, contains('secure-recent-migration-scrub-failed:0'));
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

class ThrowingEncryptedFileStore extends EncryptedFileStore {
  ThrowingEncryptedFileStore()
      : super(protectedData: const TestProtectedDataService());

  @override
  Future<File> writeBytes({
    required String collection,
    required String id,
    required String extension,
    required List<int> bytes,
    required String kind,
    bool compress = true,
  }) {
    throw StateError('write blocked');
  }
}
