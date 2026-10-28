import 'dart:convert';
import 'package:autoteleprompter/features/settings/models/app_hotkey.dart';
import 'package:autoteleprompter/features/settings/providers/hotkey_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stable defaults and independent device-only persistence', () async {
    final notifier = HotkeyNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(notifier.state.labelFor(AppHotkeyAction.enterFullscreen), 'F5');
    expect(notifier.state.labelFor(AppHotkeyAction.exitFullscreen), 'F3');
    expect(notifier.state.labelFor(AppHotkeyAction.previousBookmark), 'F6');
    expect(notifier.state.labelFor(AppHotkeyAction.nextBookmark), 'F7');
    expect(notifier.state.labelFor(AppHotkeyAction.toggleBookmark), 'F8');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sentinel-script', 'keep');
    expect(
      await notifier.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.keyJ, control: true),
      ),
      isNull,
    );
    expect(
      await notifier.setBinding(AppHotkeyAction.previousBookmark, null),
      isNull,
    );
    final reloaded = HotkeyNotifier();
    addTearDown(reloaded.dispose);
    await reloaded.ready;
    expect(
      reloaded.state.labelFor(AppHotkeyAction.nextBookmark),
      'Ctrl+J'.toUpperCase().replaceFirst('CTRL', 'Ctrl'),
    );
    expect(reloaded.state.labelFor(AppHotkeyAction.previousBookmark), 'Off');
    expect(prefs.getString('sentinel-script'), 'keep');
  });

  test(
    'edits queued during initial load and rapid changes keep latest',
    () async {
      final notifier = HotkeyNotifier();
      addTearDown(notifier.dispose);
      final first = notifier.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.f9),
      );
      final second = notifier.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.f10),
      );
      expect(await first, isNull);
      expect(await second, isNull);
      expect(notifier.state.labelFor(AppHotkeyAction.nextBookmark), 'F10');
      final prefs = await SharedPreferences.getInstance();
      final restored = HotkeyBindings.fromJson(
        jsonDecode(prefs.getString(HotkeyNotifier.preferenceKey)!),
      );
      expect(restored.labelFor(AppHotkeyAction.nextBookmark), 'F10');
    },
  );

  test('conflicts and reset conflicts never steal another command', () async {
    final notifier = HotkeyNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    expect(
      await notifier.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.f5),
      ),
      isNotNull,
    );
    expect(
      await notifier.setBinding(AppHotkeyAction.enterFullscreen, null),
      isNull,
    );
    expect(
      await notifier.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.f5),
      ),
      isNull,
    );
    expect(
      await notifier.resetBinding(AppHotkeyAction.enterFullscreen),
      isNotNull,
    );
    expect(notifier.state.labelFor(AppHotkeyAction.enterFullscreen), 'Off');
    expect(await notifier.resetAll(), isNull);
    for (final action in AppHotkeyAction.values) {
      expect(notifier.state.isDefault(action), isTrue);
    }
  });

  test(
    'corrupt, unknown-version and duplicate settings recover safely',
    () async {
      for (final raw in [
        '{bad',
        '{"version":2,"bindings":{}}',
        jsonEncode({
          'version': 1,
          'bindings': {
            'nextBookmark': const HotkeyBinding(LogicalKeyboardKey.f5).toJson(),
          },
        }),
      ]) {
        SharedPreferences.setMockInitialValues({
          HotkeyNotifier.preferenceKey: raw,
        });
        final notifier = HotkeyNotifier();
        await notifier.ready;
        expect(notifier.state.loaded, isTrue);
        for (final action in AppHotkeyAction.values) {
          expect(notifier.state.isDefault(action), isTrue);
        }
        notifier.dispose();
      }
    },
  );

  test(
    'standalone letters digits and navigation persist without modifiers',
    () async {
      final notifier = HotkeyNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;
      for (final key in [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit9,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        final binding = HotkeyBinding(key);
        expect(binding.validationError, isNull, reason: binding.label);
        expect(
          await notifier.setBinding(AppHotkeyAction.previousBookmark, binding),
          isNull,
        );
        final reloaded = HotkeyNotifier();
        await reloaded.ready;
        expect(
          reloaded.state.bindingFor(AppHotkeyAction.previousBookmark),
          binding,
        );
        reloaded.dispose();
      }
    },
  );

  test('standalone ArrowLeft conflicts do not replace either action', () async {
    final notifier = HotkeyNotifier();
    addTearDown(notifier.dispose);
    await notifier.ready;
    const arrow = HotkeyBinding(LogicalKeyboardKey.arrowLeft);
    expect(
      await notifier.setBinding(AppHotkeyAction.previousBookmark, arrow),
      isNull,
    );
    expect(
      await notifier.setBinding(AppHotkeyAction.nextBookmark, arrow),
      contains('Previous bookmark'),
    );
    final reloaded = HotkeyNotifier();
    addTearDown(reloaded.dispose);
    await reloaded.ready;
    expect(reloaded.state.bindingFor(AppHotkeyAction.previousBookmark), arrow);
    expect(reloaded.state.isDefault(AppHotkeyAction.nextBookmark), isTrue);
  });

  test(
    'modified navigation persists and exact chords stay independent',
    () async {
      final notifier = HotkeyNotifier();
      addTearDown(notifier.dispose);
      await notifier.ready;
      const plain = HotkeyBinding(LogicalKeyboardKey.arrowLeft);
      const modified = HotkeyBinding(
        LogicalKeyboardKey.arrowLeft,
        control: true,
      );
      expect(
        await notifier.setBinding(AppHotkeyAction.previousBookmark, plain),
        isNull,
      );
      expect(
        await notifier.setBinding(AppHotkeyAction.nextBookmark, modified),
        isNull,
      );
      expect(
        await notifier.setBinding(AppHotkeyAction.toggleBookmark, modified),
        contains('Next bookmark'),
      );
      final reloaded = HotkeyNotifier();
      addTearDown(reloaded.dispose);
      await reloaded.ready;
      expect(
        reloaded.state.bindingFor(AppHotkeyAction.previousBookmark),
        plain,
      );
      expect(reloaded.state.bindingFor(AppHotkeyAction.nextBookmark), modified);
      expect(reloaded.state.isDefault(AppHotkeyAction.toggleBookmark), isTrue);
    },
  );

  test('editing controls and OS chords stay reserved', () {
    for (final binding in [
      const HotkeyBinding(LogicalKeyboardKey.escape),
      const HotkeyBinding(LogicalKeyboardKey.enter),
      const HotkeyBinding(LogicalKeyboardKey.space),
      const HotkeyBinding(LogicalKeyboardKey.tab),
      const HotkeyBinding(LogicalKeyboardKey.delete),
      const HotkeyBinding(LogicalKeyboardKey.backspace),
      const HotkeyBinding(LogicalKeyboardKey.keyA, control: true),
      const HotkeyBinding(LogicalKeyboardKey.keyV, control: true, shift: true),
      const HotkeyBinding(LogicalKeyboardKey.keyJ, control: true, alt: true),
      const HotkeyBinding(LogicalKeyboardKey.keyJ, meta: true),
      const HotkeyBinding(LogicalKeyboardKey.f4, alt: true),
    ]) {
      expect(binding.validationError, isNotNull, reason: binding.label);
    }
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
    ]) {
      for (final binding in [
        HotkeyBinding(key, control: true),
        HotkeyBinding(key, shift: true),
        HotkeyBinding(key, alt: true),
        HotkeyBinding(key, control: true, shift: true),
        HotkeyBinding(key, control: true, alt: true),
      ]) {
        expect(binding.validationError, isNull, reason: binding.label);
      }
      expect(HotkeyBinding(key, meta: true).validationError, isNotNull);
    }
    expect(
      const HotkeyBinding(
        LogicalKeyboardKey.keyF,
        control: true,
        shift: true,
      ).validationError,
      isNull,
    );
    expect(const HotkeyBinding(LogicalKeyboardKey.f24).validationError, isNull);
    expect(
      const HotkeyBinding(LogicalKeyboardKey.keyJ, shift: true).validationError,
      isNull,
    );
  });

  testWidgets(
    'standalone keys dispatch outside editing but preserve typing and caret',
    (tester) async {
      var bindings = HotkeyBindings();
      var editingText = false;
      final actions = <AppHotkeyAction>[];
      bool handler(KeyEvent event) {
        final action = bindings.actionFor(event, editingText: editingText);
        if (action != null) actions.add(action);
        return action != null;
      }

      HardwareKeyboard.instance.addHandler(handler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));
      for (final key in [
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        bindings = HotkeyBindings().withBinding(
          AppHotkeyAction.previousBookmark,
          HotkeyBinding(key),
        );
        actions.clear();
        editingText = false;
        await tester.sendKeyEvent(key);
        expect(actions, [
          AppHotkeyAction.previousBookmark,
        ], reason: key.keyLabel);
        actions.clear();
        editingText = true;
        await tester.sendKeyEvent(key);
        expect(actions, isEmpty, reason: key.keyLabel);
      }
      bindings = HotkeyBindings().withBinding(
        AppHotkeyAction.previousBookmark,
        const HotkeyBinding(LogicalKeyboardKey.keyJ, shift: true),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(actions, isEmpty);
      editingText = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(actions, [AppHotkeyAction.previousBookmark]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      // Modified arrows/Home/End/Page keys are valid outside editing, but all
      // must remain native caret/selection commands in an editable context.
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        for (final binding in [
          HotkeyBinding(key, control: true),
          HotkeyBinding(key, shift: true),
          HotkeyBinding(key, alt: true),
          HotkeyBinding(key, control: true, shift: true),
          HotkeyBinding(key, control: true, alt: true),
        ]) {
          actions.clear();
          bindings = HotkeyBindings().withBinding(
            AppHotkeyAction.previousBookmark,
            binding,
          );
          final modifiers = [
            if (binding.control) LogicalKeyboardKey.controlLeft,
            if (binding.alt) LogicalKeyboardKey.altLeft,
            if (binding.shift) LogicalKeyboardKey.shiftLeft,
          ];
          for (final modifier in modifiers) {
            await tester.sendKeyDownEvent(modifier);
          }
          editingText = false;
          await tester.sendKeyEvent(key);
          expect(actions, [
            AppHotkeyAction.previousBookmark,
          ], reason: binding.label);
          actions.clear();
          editingText = true;
          await tester.sendKeyEvent(key);
          expect(actions, isEmpty, reason: binding.label);
          for (final modifier in modifiers.reversed) {
            await tester.sendKeyUpEvent(modifier);
          }
        }
      }
    },
  );

  test('malformed override cannot introduce reserved shortcuts', () {
    final bindings = HotkeyBindings.fromJson({
      'version': 1,
      'bindings': {
        'searchScript': {'key': LogicalKeyboardKey.keyC.keyId, 'control': true},
        'nextBookmark': {'key': LogicalKeyboardKey.f9.keyId, 'control': 'true'},
        'previousBookmark': {'key': -12345},
        'toggleBookmark': null,
      },
    });
    expect(bindings.isDefault(AppHotkeyAction.searchScript), isTrue);
    expect(bindings.isDefault(AppHotkeyAction.nextBookmark), isTrue);
    expect(bindings.isDefault(AppHotkeyAction.previousBookmark), isTrue);
    expect(bindings.bindingFor(AppHotkeyAction.toggleBookmark), isNull);
  });

  testWidgets('keydown only and exact modifiers, no held-key toggles', (
    tester,
  ) async {
    final bindings = HotkeyBindings();
    final actions = <AppHotkeyAction?>[];
    bool handler(KeyEvent event) {
      actions.add(bindings.actionFor(event, editingText: true));
      return false;
    }

    HardwareKeyboard.instance.addHandler(handler);
    addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    expect(actions.whereType<AppHotkeyAction>(), [
      AppHotkeyAction.toggleBookmark,
    ]);
    actions.clear();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(actions.whereType<AppHotkeyAction>(), isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(actions.whereType<AppHotkeyAction>(), [
      AppHotkeyAction.searchScript,
    ]);
  });
}
