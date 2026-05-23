import 'package:autoteleprompter/features/script/widgets/editor/components/global_selection_overlay.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native drag promotion preserves reverse anchor and focus',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);

    fixture.key.currentState!.extendNativeBlockSelection(
      0,
      const TextSelection(baseOffset: 5, extentOffset: 2),
    );
    await tester.pumpAndSettle();

    final session = fixture.key.currentState!.selectionSessionSnapshot;
    expect(session, isNotNull);
    expect(session!.anchor.toString(), '0:5');
    expect(session.focus.toString(), '0:2');
    expect(fixture.controllers.first.externalSelection!.start, 2);
    expect(fixture.controllers.first.externalSelection!.end, 5);
  });

  testWidgets('native drag promotion preserves forward anchor and focus',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);

    fixture.key.currentState!.extendNativeBlockSelection(
      0,
      const TextSelection(baseOffset: 1, extentOffset: 4),
    );
    await tester.pumpAndSettle();

    final session = fixture.key.currentState!.selectionSessionSnapshot;
    expect(session, isNotNull);
    expect(session!.anchor.toString(), '0:1');
    expect(session.focus.toString(), '0:4');
    expect(fixture.controllers.first.externalSelection!.start, 1);
    expect(fixture.controllers.first.externalSelection!.end, 4);
  });

  testWidgets('native full-block drag promotion is ignored unless explicit',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['word']);
    final state = fixture.key.currentState!;

    state.extendNativeBlockSelection(
      0,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    await tester.pumpAndSettle();

    expect(state.hasSelection, isFalse);

    state.extendNativeBlockSelection(
      0,
      const TextSelection(baseOffset: 0, extentOffset: 4),
      allowFullBlock: true,
    );
    await tester.pumpAndSettle();

    final session = state.selectionSessionSnapshot;
    expect(session, isNotNull);
    expect(session!.anchor.toString(), '0:0');
    expect(session.focus.toString(), '0:4');
    expect(fixture.controllers.first.externalSelection!.start, 0);
    expect(fixture.controllers.first.externalSelection!.end, 4);
  });

  testWidgets('select all anchors script start and focuses script end',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);

    fixture.key.currentState!.selectAll();
    await tester.pumpAndSettle();

    final session = fixture.key.currentState!.selectionSessionSnapshot;
    expect(session, isNotNull);
    expect(session!.anchor.toString(), '0:0');
    expect(session.focus.toString(), '1:6');
    expect(
        fixture.controllers.every((controller) => controller.isGlobalSelected),
        isTrue);
  });

  testWidgets('clearSelection removes stale overlay handle positions',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);
    final state = fixture.key.currentState!;

    state.selectAll();
    await tester.pumpAndSettle();

    state.clearSelection();
    await tester.pump();

    expect(state.hasSelection, isFalse);
    expect(state.debugSelectionSummary, contains('handles:---'));
    expect(
      fixture.controllers.any(
        (controller) =>
            controller.isGlobalSelected || controller.externalSelection != null,
      ),
      isFalse,
    );
  });

  testWidgets('same-block body drag stays native-owned until pointer-up',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);
    final state = fixture.key.currentState!;
    final blockFinder = find.byKey(fixture.blockKeys.first);
    final start = tester.getTopLeft(blockFinder) + const Offset(12, 12);

    state.startDragging(start);
    state.updateDragging(start + const Offset(80, 0));
    final overlayOwned = state.endDragging();
    await tester.pumpAndSettle();

    expect(overlayOwned, isFalse);
    expect(state.hasSelection, isFalse);
  });

  testWidgets('candidate pointer down preserves existing overlay selection',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);
    final state = fixture.key.currentState!;
    state.setKeyboardSelection(
      anchorBlock: 0,
      anchorOffset: 1,
      focusBlock: 1,
      focusOffset: 3,
    );
    await tester.pumpAndSettle();

    final before = state.selectionSessionSnapshot!;
    final start = tester.getTopLeft(find.byKey(fixture.blockKeys.first)) +
        const Offset(12, 12);
    state.startDragging(start);
    state.updateDragging(start + const Offset(12, 0));
    final overlayOwned = state.endDragging();
    await tester.pumpAndSettle();

    final after = state.selectionSessionSnapshot!;
    expect(overlayOwned, isFalse);
    expect(after.anchor.toString(), before.anchor.toString());
    expect(after.focus.toString(), before.focus.toString());
    expect(state.hasSelection, isTrue);
  });

  testWidgets('outside pointer down is not a replacement candidate',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['abcdef', 'ghijkl']);
    final state = fixture.key.currentState!;
    state.setKeyboardSelection(
      anchorBlock: 0,
      anchorOffset: 1,
      focusBlock: 1,
      focusOffset: 3,
    );
    await tester.pumpAndSettle();

    final before = state.selectionSessionSnapshot!;
    final startedInsideEditable = state.startDragging(const Offset(-80, -80));
    state.updateDragging(const Offset(-60, -60));
    final overlayOwned = state.endDragging();
    await tester.pumpAndSettle();

    final after = state.selectionSessionSnapshot!;
    expect(startedInsideEditable, isFalse);
    expect(overlayOwned, isFalse);
    expect(after.anchor.toString(), before.anchor.toString());
    expect(after.focus.toString(), before.focus.toString());
    expect(state.hasSelection, isTrue);
  });

  testWidgets('cross-block body drag freezes pointer-down anchor',
      (tester) async {
    final fixture =
        await _pumpOverlay(tester, ['first block', 'middle', 'final block']);
    final state = fixture.key.currentState!;
    final start = tester.getCenter(find.byKey(fixture.blockKeys[0]));
    final end = tester.getCenter(find.byKey(fixture.blockKeys[2]));

    state.startDragging(start);
    state.updateDragging(end);
    final sessionBeforeUp = state.selectionSessionSnapshot;
    final overlayOwned = state.endDragging();
    await tester.pumpAndSettle();

    expect(overlayOwned, isTrue);
    expect(sessionBeforeUp, isNotNull);
    expect(sessionBeforeUp!.anchor.block, 0);
    expect(sessionBeforeUp.focus.block, 2);
    expect(state.selectionSessionSnapshot!.anchor.block, 0);
    expect(state.selectionSessionSnapshot!.focus.block, 2);
  });

  testWidgets('keyboard overlay metadata keeps space-only rows selectable',
      (tester) async {
    final fixture = await _pumpOverlay(tester, ['before', ' ', 'after']);
    final state = fixture.key.currentState!;

    state.setKeyboardSelection(
      anchorBlock: 0,
      anchorOffset: fixture.controllers[0].text.length,
      focusBlock: 1,
      focusOffset: 0,
    );
    await tester.pumpAndSettle();

    expect(state.selectionSessionSnapshot!.focus.toString(), '1:0');

    state.setKeyboardSelection(
      anchorBlock: 0,
      anchorOffset: fixture.controllers[0].text.length,
      focusBlock: 2,
      focusOffset: 0,
    );
    await tester.pumpAndSettle();

    expect(fixture.controllers[1].externalSelection!.start, 0);
    expect(fixture.controllers[1].externalSelection!.end, 1);
  });
}

Future<_OverlayFixture> _pumpOverlay(
  WidgetTester tester,
  List<String> texts,
) async {
  final controllers =
      texts.map((text) => MarkupController(text: text)).toList();
  final blockKeys = List.generate(texts.length, (_) => GlobalKey());
  final overlayKey = GlobalKey<GlobalSelectionOverlayState>();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GlobalSelectionOverlay(
          key: overlayKey,
          controllers: controllers,
          blockKeys: blockKeys,
          settings: const AppSettings(),
          onSelectionChanged: () {},
          child: Column(
            children: [
              for (var i = 0; i < controllers.length; i++)
                TextField(
                  key: blockKeys[i],
                  controller: controllers[i],
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _OverlayFixture(
    key: overlayKey,
    controllers: controllers,
    blockKeys: blockKeys,
  );
}

class _OverlayFixture {
  final GlobalKey<GlobalSelectionOverlayState> key;
  final List<MarkupController> controllers;
  final List<GlobalKey> blockKeys;

  _OverlayFixture({
    required this.key,
    required this.controllers,
    required this.blockKeys,
  });
}
