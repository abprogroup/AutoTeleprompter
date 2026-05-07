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
}
