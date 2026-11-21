import 'dart:convert';

import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore extends SecureScriptStore {
  final records = <String, String>{};
  bool failNext = false;
  @override
  Future<SecureScriptData?> read(String? recordId) async => records.containsKey(recordId)
      ? SecureScriptData(text: records[recordId]!) : null;
  @override
  Future<String> save({
    required String recordId,
    required String text,
    String? historyJson,
  }) async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated failure');
    }
    records[recordId] = text;
    return recordId;
  }
}

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(
        lastScriptTitle: 'Active',
        lastScriptSessionId: 'active-id',
        cloudAutoSyncOnSave: true,
      );
}

class _NoSyncSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings(
        lastScriptTitle: 'Active',
        lastScriptSessionId: 'active-id',
        cloudAutoSyncOnSave: false,
      );
}

class _RestoredSettings extends SettingsNotifier {
  _RestoredSettings(this.recents);
  final List<String> recents;
  @override
  AppSettings build() => AppSettings(recentScripts: recents);
}

class _ReopenedScript extends ScriptNotifier {
  @override
  Script? build() => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _MemoryStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({'last_script_title': 'Active'});
    store = _MemoryStore();
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        scriptLibraryStoreProvider.overrideWithValue(store),
      ],
    );
  });
  tearDown(() => container.dispose());

  test('silent save stays silent and later import retains the persisted entry', () async {
    var notifications = 0;
    final subscription = container.listen(settingsProvider, (_, _) => notifications++);
    final library = container.read(settingsProvider.notifier);
    await library.saveScript('silent content', title: 'Silent', sessionId: 'silent', isSilent: true);
    expect(notifications, 0);
    expect(container.read(settingsProvider).recentScripts, isEmpty);
    expect(await library.addScriptToLibrary(title: 'silent', text: 'duplicate'), isNull);
    expect(notifications, 0);
    await library.addScriptToLibrary(title: 'Imported', text: 'content',
        style: {'scriptBgColor': 0xFFABCDEF, 'fontSize': 32.0});
    expect(container.read(settingsProvider).recentScripts.length, 2);
    final prefs = await SharedPreferences.getInstance();
    final imported = jsonDecode(prefs.getStringList('recentScripts')!.first);
    expect(imported['style']['scriptBgColor'], 0xFFABCDEF);
    expect(imported['style']['fontSize'], 32.0);
    subscription.close();
  });

  test('named empty creation, rename and reopen retain identity and empty content', () async {
    final library = container.read(settingsProvider.notifier);
    final created = await library.addScriptToLibrary(title: 'Draft', text: '');
    final id = created!['sessionId'] as String;
    expect(await library.renameLibraryScript(id, 'Opening draft'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    final savedRecents = prefs.getStringList('recentScripts')!;
    container.dispose();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _RestoredSettings(savedRecents)),
      scriptLibraryStoreProvider.overrideWithValue(store),
      scriptProvider.overrideWith(_ReopenedScript.new),
    ]);
    final metadata = Map<String, dynamic>.from(jsonDecode(savedRecents.single));
    final reopened = await store.readFromMetadata(metadata);
    expect(reopened, isNotNull);
    await container.read(settingsProvider.notifier).activateRecentScript(metadata);
    container.read(scriptProvider.notifier).loadText(reopened!.text,
      title: metadata['title'] as String, sessionId: id, persist: false);
    final script = container.read(scriptProvider)!;
    expect(script.title, 'Opening draft');
    expect(script.sessionId, id);
    expect(script.rawText, '');
    expect(container.read(settingsProvider).recentScripts.length, 1);
  });

  test('clearing a named script stores empty content; anonymous reset creates no record', () async {
    container.dispose();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_NoSyncSettings.new),
      scriptLibraryStoreProvider.overrideWithValue(store),
    ]);
    final library = container.read(settingsProvider.notifier);
    await library.saveScript('text', title: 'Existing', sessionId: 'existing');
    await library.saveScript('', title: 'Existing', sessionId: 'existing');
    expect(store.records['existing'], '');
    expect(container.read(settingsProvider).recentScripts.length, 1);
    await library.saveScript('', title: '');
    expect(store.records.length, 1);
  });

  test(
    'batch persists all records without activating or external syncing',
    () async {
      final notifier = container.read(settingsProvider.notifier);
      final results = await Future.wait([
        notifier.addScriptToLibrary(
          title: 'One.txt',
          text: 'one',
          sourcePath: r'C:\source\One.txt',
        ),
        notifier.addScriptToLibrary(
          title: 'Two.txt',
          text: 'two',
          sourcePath: r'C:\source\Two.txt',
        ),
      ]);
      expect(results.every((e) => e != null), isTrue);
      final state = container.read(settingsProvider);
      expect(state.recentScripts.length, 2);
      expect(state.lastScriptTitle, 'Active');
      expect(state.lastScriptSessionId, 'active-id');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_script_title'), 'Active');
      expect(prefs.getStringList('recentScripts')?.length, 2);
      expect(store.records.values.toSet(), {'one', 'two'});
    },
  );

  test(
    'duplicates never overwrite; named empty scripts remain in library',
    () async {
      final notifier = container.read(settingsProvider.notifier);
      final first = await notifier.addScriptToLibrary(
        title: 'Blank script',
        text: '',
      );
      expect(first, isNotNull);
      expect(
        await notifier.addScriptToLibrary(
          title: 'blank SCRIPT',
          text: 'overwrite',
        ),
        isNull,
      );
      expect(store.records.length, 1);
      expect(store.records.values.single, '');
      expect(
        await notifier.renameLibraryScript(
          first!['sessionId'] as String,
          'Named script',
        ),
        isTrue,
      );
      final meta = jsonDecode(
        container.read(settingsProvider).recentScripts.single,
      );
      expect(meta['title'], 'Named script');
    },
  );

  test(
    'source duplicate is case insensitive and failed write releases queue',
    () async {
      final notifier = container.read(settingsProvider.notifier);
      store.failNext = true;
      await expectLater(
        notifier.addScriptToLibrary(title: 'Failure', text: 'x'),
        throwsStateError,
      );
      await notifier.addScriptToLibrary(
        title: 'One',
        text: 'one',
        sourcePath: r'C:\source\one.txt',
      );
      expect(
        await notifier.addScriptToLibrary(
          title: 'Different name',
          text: 'bad',
          sourcePath: 'c:/SOURCE/one.txt',
        ),
        isNull,
      );
      expect(container.read(settingsProvider).recentScripts.length, 1);
    },
  );

  test(
    'concurrent editor saves and folder imports preserve every library entry',
    () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_NoSyncSettings.new),
          scriptLibraryStoreProvider.overrideWithValue(store),
        ],
      );
      final notifier = container.read(settingsProvider.notifier);
      await Future.wait([
        notifier.saveScript(
          'active edit',
          title: 'Active',
          sessionId: 'active-id',
        ),
        notifier.addScriptToLibrary(title: 'Imported', text: 'imported'),
        notifier.saveScript(
          'silent copy',
          title: 'Silent',
          sessionId: 'silent-id',
          isSilent: true,
        ),
        notifier.addScriptToLibrary(title: 'Imported two', text: 'two'),
      ]);
      final state = container.read(settingsProvider);
      expect(
        state.recentScripts.map((raw) => jsonDecode(raw)['title']).toSet(),
        {'Active', 'Silent', 'Imported', 'Imported two'},
      );
      expect(state.lastScriptTitle, 'Active');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recentScripts')?.length, 4);
    },
  );
}
