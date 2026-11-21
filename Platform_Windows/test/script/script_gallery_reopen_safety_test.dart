import 'dart:convert';
import 'package:autoteleprompter/core/security/secure_script_store.dart';
import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/widgets/script_editor_screen.dart';
import 'package:autoteleprompter/features/script/widgets/script_gallery_screen.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReopenStore extends SecureScriptStore {
  _ReopenStore(this.mode);
  final String mode;
  int saves = 0;
  @override
  Future<SecureScriptData?> read(String? recordId) async {
    if (mode == 'error') throw StateError('simulated unreadable record');
    return mode == 'missing' ? null : const SecureScriptData(text: '');
  }
  @override
  Future<String> save({required String recordId, required String text, String? historyJson}) async {
    saves++;
    return recordId;
  }
}

class _GallerySettings extends SettingsNotifier {
  _GallerySettings(this.id);
  final String id;
  @override
  AppSettings build() => AppSettings(
    lastScriptTitle: 'Active script', lastScriptSessionId: 'active-fixture',
    cloudAutoSyncOnSave: false, checkUpdatesOnStartup: false,
    windowsOnboardingVersionSeen: 'windows-onboarding-v1',
    recentScripts: [jsonEncode({'title': 'Draft $id', 'type': 'TEMP',
      'sessionId': id, SecureScriptStore.recordIdKey: id,
      SecureScriptStore.storageVersionKey: SecureScriptStore.storageVersion})],
  );
}

class _ActiveScript extends ScriptNotifier {
  @override
  Script build() => const Script(id: 'active-fixture', sessionId: 'active-fixture',
    title: 'Active script', rawText: 'Keep this active content', words: [], isRtl: false);
}

void main() {
  for (final mode in ['error', 'missing', 'empty']) {
    testWidgets('gallery reopen $mode preserves payload safety', (tester) async {
      SharedPreferences.setMockInitialValues({'checkUpdatesOnStartup': false});
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      final store = _ReopenStore(mode);
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith(() => _GallerySettings('reopen-$mode')),
        scriptProvider.overrideWith(_ActiveScript.new),
        scriptLibraryStoreProvider.overrideWithValue(store),
        authProvider.overrideWith((ref) => AuthNotifier(
          accountBackendConfig: const AccountBackendConfig(enabled: false))),
      ]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        container.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await container.read(authProvider.notifier).initialized;
      final original = container.read(scriptProvider);
      await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: const MaterialApp(home: ScriptGalleryScreen())));
      await tester.pumpAndSettle();
      final title = find.text('Draft reopen-$mode');
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      if (mode == 'empty') {
        expect(find.byType(ScriptEditorScreen), findsOneWidget);
        expect(container.read(scriptProvider)?.title, 'Draft reopen-empty');
        expect(container.read(scriptProvider)?.sessionId, 'reopen-empty');
        expect(container.read(scriptProvider)?.rawText, '');
      } else {
        expect(find.byType(ScriptEditorScreen), findsNothing);
        expect(find.textContaining('Nothing was replaced'), findsOneWidget);
        expect(container.read(scriptProvider), same(original));
        expect(store.saves, 0);
        expect(container.read(settingsProvider).lastScriptSessionId, 'active-fixture');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
