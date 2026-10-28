import 'package:autoteleprompter/features/script/models/script.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:autoteleprompter/features/teleprompter/models/alignment_result.dart';
import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/features/teleprompter/widgets/teleprompter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:async';

class ViewSettings extends SettingsNotifier {
  ViewSettings(this.rotation, this.mirror);
  final int rotation;
  final bool mirror;
  @override
  AppSettings build() => AppSettings(
    fontSize: 24,
    scrollLead: .35,
    mirrorVertical: mirror,
    flipRotation: rotation,
  );
}

class ViewScript extends ScriptNotifier {
  ViewScript(this.script);
  final Script script;
  @override
  Script build() => script;
}

class ViewPosition extends TeleprompterNotifier {
  int jumps = 0;
  int? visibleStart, visibleEnd;
  @override
  TeleprompterState build() => const TeleprompterState();
  @override
  Future<void> stopSession() async {}
  @override
  void jumpToPosition(int index, {Script? script}) {
    jumps++;
    state = state.copyWith(confirmedWordIndex: index);
  }

  void listening(bool value) => state = state.copyWith(isListening: value);
  @override
  void setVisibleWordWindow(int? startIndex, int? endIndex) {
    visibleStart = startIndex;
    visibleEnd = endIndex;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
  });

  Future<({ProviderContainer container, ViewPosition position})> mount(
    WidgetTester tester, {
    int rotation = 0,
    bool mirror = false,
    bool hebrew = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 750);
    final raw = List.generate(
      240,
      (i) => hebrew ? 'מילה$i' : 'word$i',
    ).join(' ');
    final script = Script(
      id: 'resize-test',
      title: 'Resize fixture',
      rawText: raw,
      words: WordAligner.tokenize(raw),
      isRtl: hebrew,
      sessionId: 'resize-test',
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => ViewSettings(rotation, mirror)),
        scriptProvider.overrideWith(() => ViewScript(script)),
        teleprompterProvider.overrideWith(ViewPosition.new),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TeleprompterScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final position =
        container.read(teleprompterProvider.notifier) as ViewPosition;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return (container: container, position: position);
  }

  Finder word(int i, {bool hebrew = false}) => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data?.replaceAll(RegExp('[\u2066-\u2069]'), '') ==
            (hebrew ? 'מילה$i' : 'word$i'),
  );

  Rect transformedRect(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    final points =
        [
          Offset.zero,
          Offset(box.size.width, 0),
          Offset(0, box.size.height),
          Offset(box.size.width, box.size.height),
        ].map(box.localToGlobal).toList();
    return Rect.fromLTRB(
      points.map((p) => p.dx).reduce(math.min),
      points.map((p) => p.dy).reduce(math.min),
      points.map((p) => p.dx).reduce(math.max),
      points.map((p) => p.dy).reduce(math.max),
    );
  }

  for (final rotation in [0, 90, 180, 270]) {
    testWidgets(
      'rotation $rotation and vertical mirror retain reading anchor',
      (tester) async {
        await mount(tester, rotation: rotation, mirror: true);
        final scroll =
            tester
                .widget<SingleChildScrollView>(
                  find.byType(SingleChildScrollView).first,
                )
                .controller!;
        scroll.jumpTo(1700);
        await tester.pumpAndSettle();
        final line = find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxHeight == 3,
        );
        final horizontal = rotation == 90 || rotation == 270;
        double axis(Rect r) => horizontal ? r.center.dx : r.center.dy;
        final oldLine = axis(transformedRect(tester, line));
        final candidates = List.generate(
          240,
          (i) => (i: i, rect: transformedRect(tester, word(i))),
        );
        final closest = candidates.reduce(
          (a, b) =>
              (axis(a.rect) - oldLine).abs() <= (axis(b.rect) - oldLine).abs()
                  ? a
                  : b,
        );
        final before = axis(closest.rect) - oldLine;
        tester.view.physicalSize = const Size(1500, 980);
        await tester.pumpAndSettle();
        expect(
          axis(transformedRect(tester, word(closest.i))) -
              axis(transformedRect(tester, line)),
          closeTo(before, 1),
        );
      },
    );
  }

  testWidgets('F3 while native fullscreen entry is pending still exits', (
    tester,
  ) async {
    final entering = Completer<bool>();
    final calls = <bool>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('autoteleprompter/window'),
      (call) async {
        final enabled = call.arguments as bool;
        calls.add(enabled);
        return enabled ? entering.future : false;
      },
    );
    await mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();
    entering.complete(true);
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });

  testWidgets(
    'stale smooth target does not resume after reflow; next speech still follows',
    (tester) async {
      final h = await mount(tester);
      h.position.listening(true);
      await tester.pump();
      h.position.jumpToPosition(80);
      await tester.pump(const Duration(milliseconds: 32));
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      final scroll =
          tester
              .widget<SingleChildScrollView>(
                find.byType(SingleChildScrollView).first,
              )
              .controller!;
      final anchored = scroll.offset;
      await tester.pump(const Duration(seconds: 2));
      expect(scroll.offset, closeTo(anchored, .1));
      h.position.jumpToPosition(81);
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.offset, isNot(closeTo(anchored, .1)));
    },
  );

  testWidgets('minimize/restore metric burst retains original anchor', (
    tester,
  ) async {
    final h = await mount(tester);
    final scroll =
        tester
            .widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView).first,
            )
            .controller!;
    scroll.jumpTo(1700);
    await tester.pumpAndSettle();
    final before = scroll.offset;
    // A minimized native window can send zero metrics without a render frame.
    tester.view.physicalSize = Size.zero;
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1100, 750);
    await tester.pumpAndSettle();
    expect(scroll.offset, closeTo(before, .1));
    expect(h.position.jumps, 0);
  });

  testWidgets(
    'F5 enters, F3 exits; repeats do not toggle and Escape still exits',
    (tester) async {
      final calls = <bool>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('autoteleprompter/window'),
        (call) async {
          calls.add(call.arguments as bool);
          return call.arguments;
        },
      );
      await mount(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      expect(calls, [true]);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pump();
      expect(calls, [true, false]);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls, [true, false, true, false]);
    },
  );

  for (final hebrew in [false, true]) {
    for (final listening in [false, true]) {
      testWidgets(
        'resize preserves reading-line word, ${hebrew ? 'RTL' : 'LTR'}, listening=$listening',
        (tester) async {
          final h = await mount(tester, hebrew: hebrew);
          // User browses far from confirmed index zero; must not snap to zero.
          final scroll =
              tester
                  .widget<SingleChildScrollView>(
                    find.byType(SingleChildScrollView).first,
                  )
                  .controller!;
          scroll.jumpTo(1600);
          await tester.pumpAndSettle();
          h.position.listening(listening);
          await tester.pumpAndSettle();
          const oldLine = 750 * .35;
          final candidates = List.generate(
            240,
            (i) => (i: i, rect: tester.getRect(word(i, hebrew: hebrew))),
          );
          final closest = candidates.reduce(
            (a, b) =>
                (a.rect.center.dy - oldLine).abs() <=
                        (b.rect.center.dy - oldLine).abs()
                    ? a
                    : b,
          );
          final anchorWord = closest.i;
          final before = (closest.rect.top - oldLine) / closest.rect.height;
          final jumps = h.position.jumps;
          final index =
              h.container.read(teleprompterProvider).confirmedWordIndex;
          for (final size in [
            const Size(1600, 1000),
            const Size(1100, 750),
            const Size(1350, 850),
          ]) {
            tester.view.physicalSize = size;
            expect(
              h.position.visibleStart,
              isNull,
              reason: 'Old viewport must lose authority before reflow',
            );
            expect(h.position.visibleEnd, isNull);
            await tester.pumpAndSettle();
            final after = tester.getRect(word(anchorWord, hebrew: hebrew));
            expect(
              (after.top - size.height * .35) / after.height,
              closeTo(before, .08),
            );
            expect(
              h.container.read(teleprompterProvider).confirmedWordIndex,
              index,
            );
            expect(
              h.position.jumps,
              jumps,
              reason: 'Reflow is not a manual progress jump',
            );
            expect(h.position.visibleStart, isNotNull);
            expect(h.position.visibleEnd, isNotNull);
          }
        },
      );
    }
  }
}
