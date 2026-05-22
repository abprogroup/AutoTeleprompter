import 'dart:ui' as ui;

import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Hebrew DOCX underline and highlight ranges safely', () {
    const raw =
        '[align=right][u]עוד משהו שהבנתי בגיל 50 זה שצריך להשקיע גם בזוגיות שלי.[/u]\n'
        '[bg=#FCE5CD]הבעיה שאני לא יכול לצאת יותר לכרים.[/bg][/align=right]';

    final ranges = MarkupDecorationParser.decorationRanges(raw);
    final underline = ranges
        .where((range) => range.type == MarkupDecorationType.underline)
        .toList();
    final background = ranges
        .where((range) => range.type == MarkupDecorationType.background)
        .toList();

    expect(underline, hasLength(1));
    expect(raw.substring(underline.single.start, underline.single.end),
        contains('50'));
    expect(background, hasLength(1));
    expect(background.single.color, const Color(0xFFFCE5CD));
    expect(raw.substring(background.single.start, background.single.end),
        startsWith('הבעיה'));
    expect(MarkupDecorationParser.visibleText(raw), isNot(contains('[u]')));
    expect(MarkupDecorationParser.visibleText(raw),
        isNot(contains('[align=right]')));
  });

  test('raw and visible offsets stay stable around hidden markup', () {
    const raw = '[u]שלום [פסח][/u]';
    final rawOffset = raw.indexOf('[פסח]');
    final visibleOffset = MarkupDecorationParser.rawToVisibleOffset(
      raw,
      rawOffset,
    );

    expect(visibleOffset, 'שלום '.length);
    expect(
      MarkupDecorationParser.visibleToRawOffset(raw, visibleOffset),
      rawOffset,
    );
  });

  test('search bookkeeping maps visible matches back to raw paint ranges', () {
    const query = '\u05d1\u05d5\u05d0\u05d5 \u05e0\u05ea\u05e7\u05d3\u05dd';
    const raw = '[align=right][u]\u05e4\u05ea\u05d9\u05d7\u05d4[/u] '
        '[bg=#806000]$query[/bg] '
        '\u05d1\u05d8\u05e7\u05e1. '
        '\u05e9\u05dc\u05d1 \u05d4\u05d8\u05d1\u05e2\u05d5\u05ea'
        '[/align=right]';
    final visible = MarkupDecorationParser.visibleText(raw);
    final visibleStart = visible.indexOf(query);
    final visibleEnd = visibleStart + query.length;
    final rawStart = MarkupDecorationParser.visibleToRawOffset(
      raw,
      visibleStart,
    );
    final rawEnd = MarkupDecorationParser.visibleToRawOffset(raw, visibleEnd);
    final rawSelection =
        TextSelection(baseOffset: rawStart, extentOffset: rawEnd);
    final visibleSelection =
        MarkupDecorationParser.rawToVisibleSelection(raw, rawSelection);

    expect(
        visible.substring(visibleSelection.start, visibleSelection.end), query);
    expect(visible.substring(visibleSelection.start, visibleSelection.end),
        isNot(contains('\u05e9\u05dc\u05d1')));
    expect(rawSelection.start, lessThanOrEqualTo(raw.indexOf(query)));
    expect(rawSelection.end,
        greaterThanOrEqualTo(raw.indexOf(query) + query.length));
  });

  test('paintable decoration range trims whitespace-only styling', () {
    const blank = '[u]   [/u]';
    final blankRange = MarkupDecorationParser.decorationRanges(blank).single;
    expect(
      MarkupDecorationParser.paintableContentRange(blank, blankRange),
      isNull,
    );

    const text = '[u] \u05e9\u05dc\u05d5\u05dd [/u]';
    final range = MarkupDecorationParser.decorationRanges(text).single;
    final paintable = MarkupDecorationParser.paintableContentRange(text, range);
    expect(paintable, isNotNull);
    expect(text.substring(paintable!.start, paintable.end),
        '\u05e9\u05dc\u05d5\u05dd');
  });

  test('merges only same-row nearby decoration boxes', () {
    final merged = MarkupDecorationBoxMerger.merge(
      const [
        Rect.fromLTRB(100, 10, 150, 30),
        Rect.fromLTRB(152, 11, 210, 31),
        Rect.fromLTRB(20, 50, 80, 70),
      ],
      rowTolerance: 4,
      gapTolerance: 6,
    );

    expect(merged, hasLength(2));
    expect(merged.first.left, 100);
    expect(merged.first.right, 210);
    expect(merged.last.top, 50);
  });

  test('active selection merge gap stays precise', () {
    final merged = MarkupDecorationBoxMerger.merge(
      const [
        Rect.fromLTRB(100, 10, 150, 30),
        Rect.fromLTRB(162, 10, 220, 30),
        Rect.fromLTRB(260, 10, 320, 30),
      ],
      rowTolerance: 4,
      gapTolerance: 12,
    );

    expect(merged, hasLength(2));
    expect(merged.first.left, 100);
    expect(merged.first.right, 220);
    expect(merged.last.left, 260);
  });

  test('style highlight can bridge nearby spaces but selection stays tight',
      () {
    const boxes = [
      Rect.fromLTRB(120, 10, 180, 30),
      Rect.fromLTRB(192, 10, 260, 30),
    ];

    final styleMerged = MarkupDecorationBoxMerger.merge(
      boxes,
      rowTolerance: 4,
      gapTolerance: MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
    );
    final selectionMerged = MarkupDecorationBoxMerger.merge(
      boxes,
      rowTolerance: 4,
      gapTolerance: MarkupDecorationBoxMerger.activeSelectionGapTolerance,
    );

    expect(styleMerged, hasLength(1));
    expect(styleMerged.single.left, 120);
    expect(styleMerged.single.right, 260);
    expect(selectionMerged, hasLength(2));
  });

  test('style decoration tails keep directional rendered-editor polish', () {
    expect(MarkupDecorationBoxMerger.styleBackgroundInnerTail, 2.0);
    expect(MarkupDecorationBoxMerger.styleBackgroundVisualEndTail, 6.0);
    expect(MarkupDecorationBoxMerger.styleUnderlineVisualEndTail, 3.0);
  });

  test('selection endpoints follow painted LTR and RTL rectangle edges', () {
    const rects = [
      Rect.fromLTRB(420, 10, 520, 40),
      Rect.fromLTRB(320, 50, 480, 80),
    ];

    final ltrStart = MarkupTextLayoutGeometry.endpointForRects(
      rects,
      isRangeStart: true,
      textDirection: TextDirection.ltr,
    );
    final ltrEnd = MarkupTextLayoutGeometry.endpointForRects(
      rects,
      isRangeStart: false,
      textDirection: TextDirection.ltr,
    );
    final rtlStart = MarkupTextLayoutGeometry.endpointForRects(
      rects,
      isRangeStart: true,
      textDirection: TextDirection.rtl,
    );
    final rtlEnd = MarkupTextLayoutGeometry.endpointForRects(
      rects,
      isRangeStart: false,
      textDirection: TextDirection.rtl,
    );

    expect(ltrStart, const Offset(420, 25));
    expect(ltrEnd, const Offset(480, 65));
    expect(rtlStart, const Offset(520, 25));
    expect(rtlEnd, const Offset(320, 65));
  });

  testWidgets('RTL right-aligned decoration boxes stay on visual text',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right][u]\u05e9\u05dc\u05d5\u05dd '
        '\u05e2\u05d5\u05dc\u05dd[/u][/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);

    final range = MarkupDecorationParser.decorationRanges(raw)
        .singleWhere((item) => item.type == MarkupDecorationType.underline);
    final paintable = MarkupDecorationParser.paintableContentRange(raw, range)!;
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 24),
        withComposing: false,
      ),
      width: 500,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );

    final aligned = geometry.selectionRects(
      TextSelection(baseOffset: paintable.start, extentOffset: paintable.end),
    );
    final leftMost = aligned
        .map((rect) => rect.left)
        .reduce((value, element) => value < element ? value : element);
    final rightMost = aligned
        .map((rect) => rect.right)
        .reduce((value, element) => value > element ? value : element);

    expect(aligned, isNotEmpty);
    expect(leftMost, greaterThan(250));
    expect(rightMost, lessThanOrEqualTo(500));
  });

  testWidgets('RTL decoration alignment is not double shifted', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right][bg=#00FF00]\u05d5\u05d4\u05d1\u05ea '
        '\u05e9\u05dc\u05d9 \u05d2\u05dd \u05d0\u05d9\u05df '
        '\u05dc\u05d4 \u05d1\u05e2\u05d9\u05d4 '
        '\u05dc\u05e9\u05e7\u05e8 \u05dc\u05d9 '
        '\u05d1\u05e4\u05e8\u05e6\u05d5\u05e3. '
        '\u05d0\u05d9\u05d6\u05d4 \u05d9\u05d5\u05dd '
        '\u05d4\u05d9\u05d0 \u05e9\u05d9\u05d7\u05e7\u05d4[/bg]'
        '[/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);

    final range = MarkupDecorationParser.decorationRanges(raw).single;
    final paintable = MarkupDecorationParser.paintableContentRange(raw, range)!;
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 34),
        withComposing: false,
      ),
      width: 700,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );
    final selection = TextSelection(
      baseOffset: paintable.start,
      extentOffset: paintable.end,
    );

    final rawBoxes = geometry.selectionRects(
      selection,
      alignToVisualLine: false,
    );
    final alignedBoxes = geometry.selectionRects(selection);

    expect(rawBoxes, isNotEmpty);
    expect(alignedBoxes, hasLength(rawBoxes.length));
    for (var i = 0; i < rawBoxes.length; i++) {
      expect(
        alignedBoxes[i].center.dx,
        closeTo(rawBoxes[i].center.dx, 0.01),
        reason:
            'Flutter already returns visual RTL selection boxes; shifting them '
            'again creates the right-heavy highlight tails seen in the editor.',
      );
    }
  });

  testWidgets('LTR left-aligned decoration geometry is not shifted',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[u]English underline check[/u]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);

    final range = MarkupDecorationParser.decorationRanges(raw).single;
    final paintable = MarkupDecorationParser.paintableContentRange(raw, range)!;
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 24),
        withComposing: false,
      ),
      width: 500,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    final selection = TextSelection(
      baseOffset: paintable.start,
      extentOffset: paintable.end,
    );

    final aligned = geometry.selectionRects(selection);
    final rawBoxes = geometry.selectionRects(
      selection,
      alignToVisualLine: false,
    );

    expect(aligned, hasLength(rawBoxes.length));
    for (var i = 0; i < aligned.length; i++) {
      expect(aligned[i].left, closeTo(rawBoxes[i].left, 0.01));
      expect(aligned[i].right, closeTo(rawBoxes[i].right, 0.01));
    }
  });

  testWidgets('active selection uses rendered editor layout across nested tags',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05d0\u05d9\u05d6\u05d4 '
        '[bg=#806000]\u05d9\u05e4\u05d9\u05dd[/bg] '
        '[u]\u05d0\u05ea\u05dd[/u]. '
        '**\u05e9\u05dc\u05d1 \u05d4\u05d8\u05d1\u05e2\u05d5\u05ea**'
        '[/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 28),
        withComposing: false,
      ),
      width: 700,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );
    const rawSelection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    final rects = geometry.mergedActiveSelectionRects(
      rawSelection,
      fluidFullLine: true,
    );

    expect(rawSelection.start, 0);
    expect(rawSelection.end, raw.length);
    expect(rects, isNotEmpty);
    for (final rect in rects) {
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(700));
    }
  });

  testWidgets('partial and full selections are not double-painted inline',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05d4\u05d4\u05d9\u05d0 '
        '\u05e2\u05d5\u05e9\u05d4 \u05d8\u05d5\u05d1\u05d4[/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);

    bool hasInlineSelection(TextSpan span) {
      if (span.style?.backgroundColor != null) return true;
      final children = span.children;
      if (children == null) return false;
      return children.any(
        (child) => child is TextSpan && hasInlineSelection(child),
      );
    }

    final start = raw.indexOf('\u05d4\u05d4\u05d9\u05d0');
    final end = raw.indexOf('\u05d8\u05d5\u05d1\u05d4');
    controller.externalSelection =
        TextSelection(baseOffset: start, extentOffset: end);
    final partialSpan = controller.buildTextSpan(
      context: capturedContext,
      style: const TextStyle(fontSize: 28),
      withComposing: false,
    );
    expect(
      hasInlineSelection(partialSpan),
      isFalse,
      reason:
          'Active selection has one visual owner: the custom raw-span painter. '
          'Inline TextSpan backgrounds create a second darker/bumpy layer.',
    );

    controller
      ..isGlobalSelected = true
      ..externalSelection =
          const TextSelection(baseOffset: 0, extentOffset: raw.length);
    final fullSpan = controller.buildTextSpan(
      context: capturedContext,
      style: const TextStyle(fontSize: 28),
      withComposing: false,
    );
    expect(
      hasInlineSelection(fullSpan),
      isFalse,
      reason: 'Full-block selection must not add an inline duplicate over the '
          'fluid selection band.',
    );
  });

  testWidgets('active RTL selection aligns to right visual line',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05d1\u05d5\u05d0\u05d5 '
        '\u05e0\u05ea\u05e7\u05d3\u05dd \u05d1\u05d8\u05e7\u05e1. '
        '\u05e9\u05dc\u05d1 \u05d4\u05d8\u05d1\u05e2\u05d5\u05ea[/align=right]';
    final visible = MarkupDecorationParser.visibleText(raw);
    final start = visible.indexOf('\u05d1\u05d5\u05d0\u05d5 '
        '\u05e0\u05ea\u05e7\u05d3\u05dd');
    final end = start +
        '\u05d1\u05d5\u05d0\u05d5 '
                '\u05e0\u05ea\u05e7\u05d3\u05dd'
            .length;
    final selection = TextSelection(
      baseOffset: MarkupDecorationParser.visibleToRawOffset(raw, start),
      extentOffset: MarkupDecorationParser.visibleToRawOffset(raw, end),
    );
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 30),
        withComposing: false,
      ),
      width: 760,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );

    final unaligned = geometry.selectionRects(
      selection,
      alignToVisualLine: false,
    );
    final aligned = geometry.selectionRects(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );
    final painted = geometry.mergedActiveSelectionRects(selection);

    expect(unaligned, isNotEmpty);
    expect(aligned, isNotEmpty);
    expect(painted, isNotEmpty);
    expect(
      painted.first.center.dx,
      closeTo(aligned.first.center.dx, 0.01),
      reason: 'Search/active selection must apply the same TextAlign offset as '
          'the rendered editor so right-aligned Hebrew does not paint on the left.',
    );
  });

  testWidgets(
      'rendered RTL selection remains the final paint source with hidden tags',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right][bg=#806000]\u05d0\u05e0\u05d9 '
        '\u05e0\u05e8\u05d2\u05e2 \u05dc\u05e6\u05dc\u05d9\u05dc\u05d9 '
        '\u05e6\u05e4\u05e6\u05e4\u05d5\u05e3[/bg] '
        '\u05d1\u05dc\u05d9 [u]\u05de\u05d5\u05d6\u05d9\u05e7\u05d4 '
        '\u05d1\u05e8\u05e7\u05e2[/u][/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final rawGeometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 32),
        withComposing: false,
      ),
      width: 760,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );
    final visible = MarkupDecorationParser.visibleText(raw);
    final visibleGeometry = MarkupTextLayoutGeometry(
      textSpan: MarkupDecorationParser.visibleTextSpan(
        raw,
        style: const TextStyle(fontSize: 32),
      ),
      width: 760,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );

    final rawRects = rawGeometry.mergedActiveSelectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      fluidFullLine: true,
    );
    final visibleRects = visibleGeometry.mergedActiveSelectionRects(
      TextSelection(baseOffset: 0, extentOffset: visible.length),
      fluidFullLine: true,
    );

    expect(rawRects, isNotEmpty);
    expect(visibleRects, isNotEmpty);
    expect(
      rawGeometry.painter.text!.toPlainText().length,
      raw.length,
      reason: 'The live painter must measure the same raw-offset span as the '
          'TextField, with hidden placeholders preserving raw offset length.',
    );
    expect(
      visibleGeometry.painter.text!.toPlainText().length,
      visible.length,
      reason: 'Visible geometry is only a diagnostic comparison and search '
          'bookkeeping aid, not the live paint source.',
    );
  });

  testWidgets('full-block RTL selection covers each visual row fluidly',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05d0\u05d9\u05d6\u05d4 '
        '\u05d9\u05e4\u05d9\u05dd \u05d0\u05ea\u05dd. '
        '\u05d1\u05d5\u05d0\u05d5 \u05e0\u05ea\u05e7\u05d3\u05dd '
        '\u05d1\u05d8\u05e7\u05e1. \u05de\u05d4 \u05d6\u05d4 '
        'TEMU? \u05de\u05d2\u05e0\u05d5\u05dc\u05d9\u05d4?[/align=right]';
    const selection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 30),
        withComposing: false,
      ),
      width: 420,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );

    final tight = geometry.selectionRects(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );
    final fluid = geometry.mergedActiveSelectionRects(
      selection,
      fluidFullLine: true,
    );

    expect(tight.length, greaterThanOrEqualTo(fluid.length));
    expect(fluid, isNotEmpty);
    for (final row in fluid) {
      expect(
        row.right,
        greaterThan(400),
        reason:
            'Full-row RTL selection must align with the right-aligned visual '
            'text, not paint a phantom row on the empty left side.',
      );
      final rowBoxes = tight
          .where((box) => (box.center.dy - row.center.dy).abs() <= 6)
          .toList();
      expect(rowBoxes, isNotEmpty);
      final minLeft =
          rowBoxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
      final maxRight =
          rowBoxes.map((box) => box.right).reduce((a, b) => a > b ? a : b);
      final visibleLeft = minLeft.clamp(0.0, 420.0).toDouble();
      final visibleRight = maxRight.clamp(0.0, 420.0).toDouble();
      expect(row.left, greaterThanOrEqualTo(0));
      expect(row.right, lessThanOrEqualTo(420));
      expect(row.left, lessThanOrEqualTo(visibleLeft + 0.01));
      expect(row.right, greaterThanOrEqualTo(visibleRight - 0.01));
    }
  });

  testWidgets('full-block selection uses visual line metrics, not glyph boxes',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05d0\u05e0\u05d9 \u05e0\u05e8\u05d2\u05e2 '
        '\u05dc\u05e6\u05dc\u05d9\u05dc\u05d9 \u05e4\u05db\u05e4\u05d5\u05da '
        '\u05de\u05e9\u05d0\u05d9\u05d5\u05ea \u05dc\u05e7\u05d5\u05d7\u05d5\u05ea '
        '\u05e8\u05d5\u05d5\u05e8\u05e1 \u05d1\u05e6\u05d9\u05d9\u05e0\u05d4 '
        '\u05d8\u05d0\u05d5\u05df[/align=right]';
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        withComposing: false,
      ),
      width: 520,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );

    final bands = geometry.mergedActiveSelectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      fluidFullLine: true,
    );
    final lines = geometry.painter
        .computeLineMetrics()
        .where((line) => line.width > 0)
        .toList(growable: false);
    final boxes = geometry.selectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );

    expect(bands, hasLength(lines.length));
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final expectedLeft = 520 - line.width;
      final rowBoxes = boxes
          .where((box) => (box.center.dy - bands[i].center.dy).abs() <= 6)
          .toList();
      final minBoxLeft = rowBoxes
          .map((box) => box.left)
          .fold<double>(expectedLeft, (a, b) => a < b ? a : b);
      final maxBoxRight = rowBoxes
          .map((box) => box.right)
          .fold<double>(520, (a, b) => a > b ? a : b);
      expect(bands[i].left, lessThanOrEqualTo(minBoxLeft + 0.01));
      expect(bands[i].right, greaterThanOrEqualTo(maxBoxRight - 0.01));
    }
  });

  testWidgets('full-block LTR selection uses visual line metrics',
      (tester) async {
    const raw = 'These women are here for a reason. Their stories teach '
        'powerful truth about the character of God.';
    final geometry = MarkupTextLayoutGeometry(
      textSpan: const TextSpan(
        text: raw,
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      width: 360,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );

    final bands = geometry.mergedActiveSelectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      fluidFullLine: true,
    );
    final lines = geometry.painter
        .computeLineMetrics()
        .where((line) => line.width > 0)
        .toList(growable: false);
    final boxes = geometry.selectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );

    expect(bands, hasLength(lines.length));
    for (var i = 0; i < lines.length; i++) {
      final rowBoxes = boxes
          .where((box) => (box.center.dy - bands[i].center.dy).abs() <= 6)
          .toList();
      final maxBoxRight = rowBoxes
          .map((box) => box.right)
          .fold<double>(lines[i].width, (a, b) => a > b ? a : b);
      expect(bands[i].left, closeTo(0, 0.01));
      expect(
        bands[i].right,
        greaterThanOrEqualTo(maxBoxRight.clamp(0.0, 360.0) - 0.01),
      );
    }
  });

  testWidgets('active selection groups mixed RTL styled boxes by line metrics',
      (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));

    const raw = '[align=right]\u05de\u05e9\u05e4\u05d8 '
        '[size=42]\u05d2\u05d3\u05d5\u05dc[/size] '
        '\u05e2\u05dd [i]\u05e0\u05d8\u05d5\u05d9[/i] '
        '\u05d5\u05e1\u05d9\u05de\u05e0\u05d9\u05dd?![/align=right]';
    const selection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        withComposing: false,
      ),
      width: 1200,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      strutStyle: const StrutStyle(
        fontSize: 42,
        height: 1.2,
        forceStrutHeight: true,
      ),
    );

    final boxes = geometry.selectionRects(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );
    final bands = geometry.mergedActiveSelectionRects(
      selection,
      fluidFullLine: true,
    );

    expect(boxes.length, greaterThan(1));
    expect(
      bands.length,
      1,
      reason:
          'Mixed font sizes/styles on one visual RTL line must still paint as '
          'one selected row band; box-center grouping splits this case.',
    );
    final minLeft =
        boxes.map((box) => box.left).reduce((a, b) => a < b ? a : b);
    final maxRight =
        boxes.map((box) => box.right).reduce((a, b) => a > b ? a : b);
    expect(bands.single.left, lessThanOrEqualTo(minLeft.clamp(0.0, 1200.0)));
    expect(
        bands.single.right, greaterThanOrEqualTo(maxRight.clamp(0.0, 1200.0)));
  });
}
