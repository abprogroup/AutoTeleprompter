import 'dart:io';

import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/widgets/script_editor_screen.dart';
import 'package:autoteleprompter/features/settings/models/app_hotkey.dart';
import 'package:autoteleprompter/features/settings/providers/hotkey_provider.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EditorSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  // Keep scripted widget QA entirely out of the user's script files/history.
  @override
  Future<void> saveScript(
    String text, {
    String? title,
    String? type,
    String? sourcePath,
    int? historyIndex,
    String? sessionId,
    bool isSilent = false,
    double? fontSize,
    String? fontFamily,
    double? lineSpacing,
    double? letterSpacing,
    double? wordSpacing,
    String? textAlign,
    int? scriptBgColor,
    int? currentWordColor,
    int? futureWordColor,
    bool? isRtl,
    String? historyJson,
  }) async {}
}

class _EditorScript extends ScriptNotifier {
  _EditorScript(this.raw);
  final String raw;
  @override
  Script build() => Script(
    id: 'editor-hotkey-fixture',
    sessionId: 'editor-hotkey-fixture',
    title: 'Hotkey fixture',
    rawText: raw,
    words: WordAligner.tokenize(raw),
    isRtl: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    String text = 'alpha beta gamma delta',
    bool pro = true,
    bool preloadHotkeys = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'auth_email': 'hotkey-fixture@example.invalid',
      'auth_is_pro': pro,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_EditorSettings.new),
        scriptProvider.overrideWith(() => _EditorScript(text)),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            accountBackendConfig: const AccountBackendConfig(enabled: false),
          ),
        ),
      ],
    );
    if (preloadHotkeys) {
      await container.read(hotkeyProvider.notifier).ready;
    }
    await container.read(authProvider.notifier).initialized;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ScriptEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return container;
  }

  TextEditingController editor(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!;

  Future<void> placeCaret(WidgetTester tester, int offset) async {
    final field = tester.widget<TextField>(find.byType(TextField).first);
    field.focusNode!.requestFocus();
    field.controller!.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
  }

  Future<void> searchChord(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> waitForBookmarkIo(WidgetTester tester) async {
    // Production bookmarks use DPAPI in an isolate; the preferences store is
    // mocked, so no bookmark file or real account data is read or written.
    // Loading and saving each cross a real-isolate/fake-widget-clock boundary.
    // Drain both phases before issuing the next user command.
    for (var phase = 0; phase < 4; phase++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('standalone arrow stays a caret key while editing', (
    tester,
  ) async {
    final container = await mount(tester);
    expect(
      await container
          .read(hotkeyProvider.notifier)
          .setBinding(
            AppHotkeyAction.previousBookmark,
            const HotkeyBinding(LogicalKeyboardKey.arrowLeft),
          ),
      isNull,
    );
    await placeCaret(tester, 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(editor(tester).selection.baseOffset, 7);
    expect(editor(tester).text, 'alpha beta gamma delta');
    expect(find.byType(AlertDialog), findsNothing);

    expect(
      await container
          .read(hotkeyProvider.notifier)
          .setBinding(
            AppHotkeyAction.previousBookmark,
            const HotkeyBinding(LogicalKeyboardKey.arrowLeft, control: true),
          ),
      isNull,
    );
    await placeCaret(tester, 10);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(editor(tester).selection.baseOffset, 6);
    expect(editor(tester).text, 'alpha beta gamma delta');
  });

  testWidgets('standalone letter does not open search while typing', (
    tester,
  ) async {
    final container = await mount(tester);
    expect(
      await container
          .read(hotkeyProvider.notifier)
          .setBinding(
            AppHotkeyAction.searchScript,
            const HotkeyBinding(LogicalKeyboardKey.keyK),
          ),
      isNull,
    );
    await placeCaret(tester, 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.text('Search script'), findsOneWidget);
  });

  testWidgets('screen initializes saved hotkeys before the first key', (
    tester,
  ) async {
    final container = await mount(tester, preloadHotkeys: false);
    expect(container.read(hotkeyProvider).loaded, isTrue);
    await placeCaret(tester, 2);
    await searchChord(tester);
    expect(find.text('Search script'), findsOneWidget);
  });

  testWidgets('custom search replaces both old editor shortcut maps', (
    tester,
  ) async {
    final container = await mount(tester);
    await placeCaret(tester, 2);
    await searchChord(tester);
    expect(find.text('Search script'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(
      await container
          .read(hotkeyProvider.notifier)
          .setBinding(
            AppHotkeyAction.searchScript,
            const HotkeyBinding(LogicalKeyboardKey.f9),
          ),
      isNull,
    );
    await placeCaret(tester, 2);
    await searchChord(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.text('Search script'), findsOneWidget);
  });

  testWidgets('shortcuts do not act behind another route or search dialog', (
    tester,
  ) async {
    await mount(tester);
    await placeCaret(tester, 2);
    final original = editor(tester).text;
    final context = tester.element(find.byType(ScriptEditorScreen));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: TextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await searchChord(tester);
    expect(find.byType(AlertDialog), findsNothing);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(editor(tester).text, original);

    await searchChord(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(editor(tester).text, original);
  });

  testWidgets('bookmark hotkey cannot bypass Pro access', (tester) async {
    await mount(tester, pro: false);
    await placeCaret(tester, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(editor(tester).text, 'alpha beta gamma delta');
    expect(find.text('Bookmarks requires Pro access.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('toggle does not replace a selected text range', (tester) async {
    await mount(tester);
    await placeCaret(tester, 6);
    editor(tester).selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 10,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.pumpAndSettle();
    expect(editor(tester).text, 'alpha beta gamma delta');
  });

  for (final raw in ['alpha beta gamma delta', 'שלום עולם כאן עכשיו']) {
    testWidgets('toggle is exact, repeat-safe and undoable: $raw', (
      tester,
    ) async {
      await mount(tester, text: raw);
      final at = raw.indexOf(' ') + 1;
      await placeCaret(tester, at);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
      await waitForBookmarkIo(tester);
      expect(
        editor(tester).text,
        '${raw.substring(0, at)}»${raw.substring(at)}',
      );

      // A different caret in the same paragraph must ADD a second bookmark,
      // never remove the nearest existing bookmark in that paragraph.
      await placeCaret(tester, editor(tester).text.length);
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await waitForBookmarkIo(tester);
      expect('»'.allMatches(editor(tester).text).length, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await waitForBookmarkIo(tester);
      expect('»'.allMatches(editor(tester).text).length, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await waitForBookmarkIo(tester);
      expect('»'.allMatches(editor(tester).text).length, 2);
    }, skip: !Platform.isWindows);
  }

  testWidgets(
    'previous and next navigate saved anchors with wraparound',
    (tester) async {
      await mount(tester);
      for (final offset in [6, 12]) {
        await placeCaret(tester, offset);
        await tester.sendKeyEvent(LogicalKeyboardKey.f8);
        await waitForBookmarkIo(tester);
      }
      final text = editor(tester).text;
      final first = text.indexOf('»');
      final last = text.lastIndexOf('»');
      await placeCaret(tester, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await waitForBookmarkIo(tester);
      expect(editor(tester).selection.baseOffset, first);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await waitForBookmarkIo(tester);
      expect(editor(tester).selection.baseOffset, last);
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await waitForBookmarkIo(tester);
      expect(editor(tester).selection.baseOffset, first);
      await tester.sendKeyEvent(LogicalKeyboardKey.f6);
      await waitForBookmarkIo(tester);
      expect(editor(tester).selection.baseOffset, last);
    },
    skip: !Platform.isWindows,
  );
}
