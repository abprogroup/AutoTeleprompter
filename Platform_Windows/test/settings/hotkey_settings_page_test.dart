import 'package:autoteleprompter/features/settings/models/app_hotkey.dart';
import 'package:autoteleprompter/features/settings/providers/hotkey_provider.dart';
import 'package:autoteleprompter/features/settings/widgets/hotkey_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> showPage(
  WidgetTester tester, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: const Scaffold(body: HotkeySettingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(HotkeySettingsPage)),
  );
}

Future<void> clickKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  if (target.evaluate().isEmpty &&
      find.byType(AlertDialog).evaluate().isEmpty) {
    // ListView only builds rows near its viewport. Move back to the header for
    // reset-all, or forward through the settings cards before ensuring visibility.
    await tester.scrollUntilVisible(
      target,
      key == 'hotkeys-reset-all' ? -250 : 250,
      scrollable:
          find
              .descendant(
                of: find.byType(HotkeySettingsPage),
                matching: find.byType(Scrollable),
              )
              .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

FilledButton saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const ValueKey('hotkey-save')));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('capture requires explicit Save and survives reloading', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    expect(saveButton(tester).onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.text('F9'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F5',
    );
    await clickKey(tester, 'hotkey-save');
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F9',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restored = await showPage(tester);
    expect(
      restored.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F9',
    );
  });

  testWidgets('conflicts show the action name and cannot be saved', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Already assigned to Exit fullscreen'),
      findsOneWidget,
    );
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F5',
    );
  });

  testWidgets('ArrowLeft can be saved for Previous bookmark and reloaded', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-previousBookmark');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
    await clickKey(tester, 'hotkey-save');
    expect(
      container
          .read(hotkeyProvider)
          .bindingFor(AppHotkeyAction.previousBookmark),
      const HotkeyBinding(LogicalKeyboardKey.arrowLeft),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restored = await showPage(tester);
    expect(
      restored
          .read(hotkeyProvider)
          .bindingFor(AppHotkeyAction.previousBookmark),
      const HotkeyBinding(LogicalKeyboardKey.arrowLeft),
    );
    await clickKey(tester, 'hotkey-change-nextBookmark');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Already assigned to Previous bookmark'),
      findsOneWidget,
    );
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      restored.read(hotkeyProvider).isDefault(AppHotkeyAction.nextBookmark),
      isTrue,
    );
  });

  testWidgets('modifier-only events wait and Ctrl+C stays reserved', (
    tester,
  ) async {
    await showPage(tester);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
    expect(find.text('Press shortcut now…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('reserved for standard editing'),
      findsOneWidget,
    );
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.text('Record another shortcut'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('Escape cancels capture without changing the binding', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F5',
    );
  });

  testWidgets('disable and per-action reset do not affect other shortcuts', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-disable-enterFullscreen');
    expect(
      container
          .read(hotkeyProvider)
          .bindingFor(AppHotkeyAction.enterFullscreen),
      isNull,
    );
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.exitFullscreen),
      'F3',
    );
    await clickKey(tester, 'hotkey-reset-enterFullscreen');
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F5',
    );
  });

  testWidgets('reset all asks first and preserves choices if canceled', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-disable-enterFullscreen');
    await clickKey(tester, 'hotkeys-reset-all');
    expect(find.text('Restore all default shortcuts?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(hotkeyProvider)
          .bindingFor(AppHotkeyAction.enterFullscreen),
      isNull,
    );
    await clickKey(tester, 'hotkeys-reset-all');
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    for (final action in AppHotkeyAction.values) {
      expect(container.read(hotkeyProvider).isDefault(action), isTrue);
    }
  });

  testWidgets('plain letters can be explicitly saved as shortcuts', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
    await clickKey(tester, 'hotkey-save');
    expect(
      container
          .read(hotkeyProvider)
          .bindingFor(AppHotkeyAction.enterFullscreen),
      const HotkeyBinding(LogicalKeyboardKey.keyJ),
    );
  });

  testWidgets('Ctrl+ArrowLeft can be saved for Next bookmark and reloaded', (
    tester,
  ) async {
    final container = await showPage(tester);
    await clickKey(tester, 'hotkey-change-nextBookmark');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
    await clickKey(tester, 'hotkey-save');
    const binding = HotkeyBinding(LogicalKeyboardKey.arrowLeft, control: true);
    expect(
      container.read(hotkeyProvider).bindingFor(AppHotkeyAction.nextBookmark),
      binding,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final restored = await showPage(tester);
    expect(
      restored.read(hotkeyProvider).bindingFor(AppHotkeyAction.nextBookmark),
      binding,
    );
  });

  testWidgets('per-action reset reports a conflict without stealing a key', (
    tester,
  ) async {
    final container = await showPage(tester);
    await container
        .read(hotkeyProvider.notifier)
        .setBinding(
          AppHotkeyAction.enterFullscreen,
          const HotkeyBinding(LogicalKeyboardKey.f9),
        );
    await container
        .read(hotkeyProvider.notifier)
        .setBinding(
          AppHotkeyAction.exitFullscreen,
          const HotkeyBinding(LogicalKeyboardKey.f5),
        );
    await tester.pumpAndSettle();
    await clickKey(tester, 'hotkey-reset-enterFullscreen');
    expect(find.text('Already assigned to Exit fullscreen.'), findsOneWidget);
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.enterFullscreen),
      'F9',
    );
    expect(
      container.read(hotkeyProvider).labelFor(AppHotkeyAction.exitFullscreen),
      'F5',
    );
  });

  testWidgets('narrow large-text page and capture dialog stay reachable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showPage(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
    await clickKey(tester, 'hotkey-change-enterFullscreen');
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await clickKey(tester, 'hotkey-save');
    expect(tester.takeException(), isNull);
    await clickKey(tester, 'hotkey-change-toggleBookmark');
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    await clickKey(tester, 'hotkey-save');
    expect(tester.takeException(), isNull);
    await clickKey(tester, 'hotkeys-reset-all');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
