import 'package:autoteleprompter/features/auth/providers/auth_provider.dart';
import 'package:autoteleprompter/features/auth/services/account_backend_config.dart';
import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/services/script_bookmark_service.dart';
import 'package:autoteleprompter/features/settings/models/app_hotkey.dart';
import 'package:autoteleprompter/features/settings/providers/hotkey_provider.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/teleprompter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presenter_viewport_test.dart'
    show ViewScript, ViewPosition, ViewSettings;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final fullscreenCalls = <bool>[];
  final scope = ScriptBookmarkService.scopeKey(
    'presenter-hotkeys-test',
    'Hotkeys',
  );
  setUp(() {
    fullscreenCalls.clear();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('autoteleprompter/window'),
      (call) async {
        final enabled = call.arguments as bool;
        fullscreenCalls.add(enabled);
        return enabled;
      },
    );
  });

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool pro = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'auth_email': 'presenter-test@example.invalid',
      'auth_is_pro': pro,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    final raw = List.generate(180, (i) => 'word$i').join(' ');
    final script = Script(
      id: 'presenter-hotkeys-test',
      title: 'Hotkeys',
      rawText: raw,
      words: WordAligner.tokenize(raw),
      isRtl: false,
      sessionId: 'presenter-hotkeys-test',
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => ViewSettings(0, false)),
        scriptProvider.overrideWith(() => ViewScript(script)),
        teleprompterProvider.overrideWith(ViewPosition.new),
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            accountBackendConfig: const AccountBackendConfig(enabled: false),
          ),
        ),
      ],
    );
    await container.read(authProvider.notifier).initialized;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TeleprompterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return container;
  }

  Future<void> settleIo(WidgetTester tester) async {
    // Encryption/load/save use several real isolate phases, interleaved with
    // widget microtasks. Drain each phase before issuing the next command.
    for (var phase = 0; phase < 4; phase++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<List<ScriptBookmark>> bookmarks(WidgetTester tester) async =>
      (await tester.runAsync(() => ScriptBookmarkService.load(scope)))!;

  testWidgets('defaults are initialized before first fullscreen key', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(fullscreenCalls, [true, false]);
  });

  testWidgets('custom fullscreen replaces old key; Escape remains safe exit', (
    tester,
  ) async {
    final container = await mount(tester);
    await container
        .read(hotkeyProvider.notifier)
        .setBinding(
          AppHotkeyAction.enterFullscreen,
          const HotkeyBinding(LogicalKeyboardKey.f9),
        );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(fullscreenCalls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(fullscreenCalls, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(fullscreenCalls, [true, false]);
  });

  testWidgets('toggle is repeat-safe and only removes current bookmark', (
    tester,
  ) async {
    final container = await mount(tester);
    final position =
        container.read(teleprompterProvider.notifier) as ViewPosition;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect((await bookmarks(tester)).map((b) => b.wordIndex), [0]);
    position.jumpToPosition(10);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect((await bookmarks(tester)).map((b) => b.wordIndex), [0, 10]);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect((await bookmarks(tester)).map((b) => b.wordIndex), [0]);
  });

  testWidgets('next previous wrap while listening without resetting speech', (
    tester,
  ) async {
    final container = await mount(tester);
    final position =
        container.read(teleprompterProvider.notifier) as ViewPosition;
    for (final index in [0, 100]) {
      position.jumpToPosition(index);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await settleIo(tester);
    }
    position.listening(true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 0);
    expect(container.read(teleprompterProvider).isListening, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 100);
    expect(container.read(teleprompterProvider).isListening, isTrue);
  });

  testWidgets('standalone arrows navigate bookmarks once and respect dialogs', (
    tester,
  ) async {
    final container = await mount(tester);
    final position =
        container.read(teleprompterProvider.notifier) as ViewPosition;
    for (final index in [0, 60, 100]) {
      position.jumpToPosition(index);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f8);
      await settleIo(tester);
    }
    final hotkeys = container.read(hotkeyProvider.notifier);
    expect(
      await hotkeys.setBinding(
        AppHotkeyAction.previousBookmark,
        const HotkeyBinding(LogicalKeyboardKey.arrowLeft),
      ),
      isNull,
    );
    expect(
      await hotkeys.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.arrowRight),
      ),
      isNull,
    );
    position.listening(true);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 60);
    expect(container.read(teleprompterProvider).isListening, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 100);

    expect(
      await hotkeys.setBinding(
        AppHotkeyAction.nextBookmark,
        const HotkeyBinding(LogicalKeyboardKey.arrowLeft, control: true),
      ),
      isNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 0);

    final context = tester.element(find.byType(TeleprompterScreen));
    showDialog<void>(
      context: context,
      builder:
          (_) => const AlertDialog(
            title: Text('Arrow input fixture'),
            content: TextField(autofocus: true),
          ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settleIo(tester);
    expect(container.read(teleprompterProvider).confirmedWordIndex, 0);
    expect(find.text('Arrow input fixture'), findsOneWidget);
  });

  testWidgets('toggle removal retains existing pause-before-remove rule', (
    tester,
  ) async {
    final container = await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    (container.read(teleprompterProvider.notifier) as ViewPosition).listening(
      true,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect(await bookmarks(tester), hasLength(1));
    expect(
      find.text('Pause speech before removing a bookmark.'),
      findsOneWidget,
    );
  });

  testWidgets('bookmarks remain Pro gated and empty navigation is harmless', (
    tester,
  ) async {
    await mount(tester, pro: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect(await bookmarks(tester), isEmpty);
    expect(find.text('Bookmarks are included with Pro.'), findsOneWidget);
  });

  testWidgets('modal input blocks all presenter commands including Escape', (
    tester,
  ) async {
    await mount(tester);
    final context = tester.element(find.byType(TeleprompterScreen));
    showDialog<void>(
      context: context,
      builder:
          (_) => const AlertDialog(
            title: Text('Fixture dialog'),
            content: TextField(autofocus: true),
          ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.sendKeyEvent(LogicalKeyboardKey.f8);
    await settleIo(tester);
    expect(fullscreenCalls, isEmpty);
    expect(await bookmarks(tester), isEmpty);
    expect(find.text('Fixture dialog'), findsOneWidget);
  });

  testWidgets('custom search removes hardcoded CtrlShiftF fallback', (
    tester,
  ) async {
    final container = await mount(tester);
    await container
        .read(hotkeyProvider.notifier)
        .setBinding(
          AppHotkeyAction.searchScript,
          const HotkeyBinding(LogicalKeyboardKey.f9),
        );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
