import 'dart:ui' as ui;

import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'RTL full selection covers punctuation boxes on their visual line',
      (tester) async {
    const raw = '[align=right]'
        '\u05ea\u05e7\u05e9\u05d9\u05d1\u05d5, \u05d0\u05ea\u05dd '
        '\u05d1\u05de\u05e6\u05d1 \u05dc\u05d0 \u05d8\u05d5\u05d1, '
        '\u05d0\u05ea\u05dd \u05db\u05dc \u05d4\u05d6\u05de\u05df '
        '\u05e8\u05e7 \u05e2\u05e1\u05d5\u05e7\u05d9\u05dd '
        '\u05d1\u05dc\u05d7\u05e4\u05e9 \u05de\u05d4 \u05dc\u05d0 '
        '\u05d1\u05e1\u05d3\u05e8 \u05d0\u05e6\u05dc '
        '\u05d4\u05e9\u05e0\u05d9. \u05d9\u05e9 \u05dc\u05db\u05dd '
        '\u05de\u05e7\u05d3\u05e9 \u05d2\u05d3\u05d5\u05dc '
        '\u05e9\u05d4\u05d2\u05e2\u05ea\u05dd \u05dc\u05e4\u05d4 '
        '\u05d4\u05e2\u05e8\u05d1, \u05db\u05d9 \u05d0\u05e0\u05d9 '
        '\u05dc\u05d0 \u05e8\u05e7 \u05e8\u05d1 \u05de\u05d7\u05ea\u05df '
        '\u05d5\u05de\u05d5\u05d4\u05dc \u05d7\u05d5\u05d1\u05d1, '
        '\u05d0\u05e0\u05d9 \u05d2\u05dd \u05de\u05d7\u05d3\u05e9 '
        '\u05e0\u05d3\u05e8\u05d9\u05dd, \u05de\u05d4 \u05d0\u05ea\u05dd '
        '\u05d0\u05d5\u05de\u05e8\u05d9\u05dd \u05e9\u05e0\u05e2\u05e9\u05d4 '
        '\u05dc\u05d4\u05dd \u05d7\u05d9\u05d3\u05d5\u05e9 '
        '\u05e7\u05d1\u05dc \u05e2\u05dd \u05d5\u05d0\u05d5\u05dc\u05dd?! '
        '\u05d1\u05d5\u05d0\u05d5 \u05d0\u05dc\u05d9\u05d9!'
        '[/align=right]';
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    const selection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        withComposing: false,
      ),
      width: 1180,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      strutStyle: const StrutStyle(
        fontSize: 30,
        height: 1.2,
        forceStrutHeight: true,
      ),
    );

    final selectedBoxes = geometry.selectionRects(
      selection,
    );
    final bands = geometry.mergedActiveSelectionRects(
      selection,
      fluidFullLine: true,
    );

    expect(bands.length, greaterThan(1));
    expect(selectedBoxes, isNotEmpty);
    for (final box in selectedBoxes.where((box) => box.width > 0)) {
      final clampedLeft = box.left.clamp(0.0, 1180.0).toDouble();
      final clampedRight = box.right.clamp(0.0, 1180.0).toDouble();
      final coveringBand = bands.where((band) {
        return _verticalOverlap(band, box) > 0.01 &&
            band.left <= clampedLeft + 0.01 &&
            band.right >= clampedRight - 0.01;
      });
      expect(
        coveringBand,
        isNotEmpty,
        reason:
            'Every selected Hebrew glyph/sign box must be covered by a band '
            'on the same visual row. Otherwise one line gains a false tail '
            'while the next line misses its last word or punctuation. '
            'box=$box clamped=[$clampedLeft, $clampedRight] bands=$bands',
      );
    }
  });

  testWidgets('partial RTL bands use tight boxes for row ownership',
      (tester) async {
    const raw = '[align=right]\u05ea\u05e7\u05e9\u05d9\u05d1\u05d5, '
        '\u05d0\u05ea\u05dd \u05d1\u05de\u05e6\u05d1 \u05dc\u05d0 '
        '\u05d8\u05d5\u05d1, \u05d0\u05ea\u05dd \u05db\u05dc '
        '\u05d4\u05d6\u05de\u05df \u05e8\u05e7 \u05e2\u05e1\u05d5\u05e7\u05d9\u05dd '
        '\u05d1\u05dc\u05d7\u05e4\u05e9 \u05de\u05d4 \u05dc\u05d0 '
        '\u05d1\u05e1\u05d3\u05e8 \u05d0\u05e6\u05dc \u05d4\u05e9\u05e0\u05d9, '
        '\u05d9\u05e9 \u05dc\u05db\u05dd \u05de\u05d6\u05dc \u05d2\u05d3\u05d5\u05dc '
        '\u05e9\u05d4\u05d2\u05e2\u05ea\u05dd \u05dc\u05e4\u05d4 \u05d4\u05e2\u05e8\u05d1, '
        '\u05db\u05d9 \u05d0\u05e0\u05d9 \u05dc\u05d0 \u05e8\u05e7 '
        '\u05e8\u05d1 \u05de\u05d7\u05ea\u05df \u05d5\u05de\u05d5\u05d4\u05dc '
        '\u05d7\u05d5\u05d1\u05d1, \u05d1\u05d5\u05d0\u05d5 '
        '\u05d0\u05dc\u05d9\u05d9![/align=right]';
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    const selection = TextSelection(baseOffset: 13, extentOffset: 260);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        withComposing: false,
      ),
      width: 1180,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      strutStyle: const StrutStyle(
        fontSize: 30,
        height: 1.2,
        forceStrutHeight: true,
      ),
    );

    final tightBoxes = geometry.selectionRects(selection);
    final bands = geometry.mergedActiveSelectionRects(
      selection,
      fluidFullLine: true,
    );

    expect(tightBoxes, isNotEmpty);
    expect(bands, isNotEmpty);
    for (final band in bands) {
      final rowBoxes = tightBoxes
          .where((box) => _verticalOverlap(box, band) > 0.01)
          .toList();
      expect(rowBoxes, isNotEmpty,
          reason: 'A selected row band must not be created unless tight '
              'rendered boxes prove selected content lives on that row.');
      final expected = rowBoxes.reduce((a, b) => a.expandToInclude(b));
      expect(band.left, closeTo(expected.left.clamp(0.0, 1180.0), 0.75));
      expect(band.right, closeTo(expected.right.clamp(0.0, 1180.0), 0.75));
    }
  });

  testWidgets('style decoration merge does not cross visual line buckets',
      (tester) async {
    const raw = '[align=right][bg=#806000]\u05e2\u05e8\u05d1 '
        '\u05d8\u05d5\u05d1 \u05d9\u05d4\u05d5\u05d3\u05d9 '
        '\u05d5\u05d9\u05d4\u05d5\u05d3\u05d9\u05d5\u05ea. '
        '\u05d1\u05d0 \u05dc\u05d9 \u05dc\u05d1\u05e8\u05da '
        '\u05e4\u05d4 \u05d6\u05d5\u05d2 '
        '\u05de\u05ea\u05d7\u05ea\u05df?! '
        '\u05d9\u05e9 \u05dc\u05e0\u05d5 \u05db\u05d0\u05df '
        '\u05d6\u05d5\u05d2 \u05e9\u05dc 10 '
        '\u05e9\u05e0\u05d9\u05dd \u05d9\u05d7\u05d3?[/bg][/align=right]';
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
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
      strutStyle: const StrutStyle(
        fontSize: 30,
        height: 1.2,
        forceStrutHeight: true,
      ),
    );

    final range = MarkupDecorationParser.decorationRanges(raw)
        .singleWhere((item) => item.type == MarkupDecorationType.background);
    final paintable = MarkupDecorationParser.paintableContentRange(raw, range)!;
    final decoration = geometry.mergedDecorationRects(
      TextSelection(baseOffset: paintable.start, extentOffset: paintable.end),
      type: MarkupDecorationType.background,
    );
    final lines = geometry.painter
        .computeLineMetrics()
        .where((line) => line.width > 0)
        .toList(growable: false);

    expect(decoration.length, lines.length);
    for (final rect in decoration) {
      final overlappedLines = lines.where((line) {
        final top = line.baseline - line.ascent;
        return _verticalOverlap(
              rect,
              Rect.fromLTWH(0, top, 520, line.height),
            ) >
            0.01;
      });
      expect(
        overlappedLines.length,
        1,
        reason:
            'Imported/style highlights must be merged inside a visual row only, '
            'never across wrapped Hebrew rows with punctuation.',
      );
    }
  });

  testWidgets(
      'active selection uses editor strut height, not tight glyph height',
      (tester) async {
    const raw = 'These women are here for a reason. '
        'Their stories teach powerful truth.';
    const selection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: const TextSpan(
        text: raw,
        style: TextStyle(
          fontSize: 30,
          height: 1.6,
          fontWeight: FontWeight.bold,
        ),
      ),
      width: 520,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      strutStyle: const StrutStyle(
        fontSize: 30,
        height: 1.6,
        forceStrutHeight: true,
      ),
    );

    final tight = geometry.selectionRects(
      selection,
      alignToVisualLine: false,
    );
    final painted = geometry.mergedActiveSelectionRects(selection);

    expect(tight, isNotEmpty);
    expect(painted, isNotEmpty);
    expect(
      painted.first.height,
      greaterThan(tight.first.height),
      reason:
          'Selection/search highlight must use the editor strut line height; '
          'tight glyph boxes look like they were measured with a smaller font.',
    );
    expect(
      painted.first.left,
      closeTo(tight.first.left, 0.01),
      reason: 'The height fix must not shift LTR horizontal coordinates.',
    );
  });

  testWidgets('layout geometry honors inherited text scaler', (tester) async {
    const raw = 'EP8S23';
    const selection = TextSelection(baseOffset: 0, extentOffset: raw.length);
    const span = TextSpan(
      text: raw,
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
    final noScale = MarkupTextLayoutGeometry(
      textSpan: span,
      width: 500,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    final scaled = MarkupTextLayoutGeometry(
      textSpan: span,
      width: 500,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.1),
    );

    final noScaleRect = noScale.mergedActiveSelectionRects(selection).single;
    final scaledRect = scaled.mergedActiveSelectionRects(selection).single;

    expect(
      scaledRect.width,
      greaterThan(noScaleRect.width),
      reason: 'Custom highlight geometry must receive the same MediaQuery text '
          'scaler as EditableText; otherwise bands end before rendered glyphs.',
    );
  });

  testWidgets('selection geometry uses rendered raw offsets with hidden tags',
      (tester) async {
    const raw = '[align=right][bg=#806000]\u05e2\u05e8\u05d1 '
        '\u05d8\u05d5\u05d1 \u05d9\u05d4\u05d5\u05d3\u05d9 '
        '\u05d5\u05d9\u05d4\u05d5\u05d3\u05d9\u05d5\u05ea. [u]'
        '\u05d1\u05d0 \u05dc\u05d9 \u05dc\u05d1\u05e8\u05da '
        '\u05e4\u05d4 \u05d6\u05d5\u05d2 \u05de\u05ea\u05d7\u05ea\u05df'
        '[/u]?! [color=#FFFFFF]\u05d9\u05e9 \u05dc\u05e0\u05d5 '
        '\u05db\u05d0\u05df \u05d6\u05d5\u05d2 \u05e9\u05dc 10 '
        '\u05e9\u05e0\u05d9\u05dd \u05d9\u05d7\u05d3?[/color][/bg]'
        '[/align=right]';
    late BuildContext capturedContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ));
    final controller = MarkupController(text: raw);
    addTearDown(controller.dispose);
    const style = TextStyle(fontSize: 30, fontWeight: FontWeight.bold);
    final geometry = MarkupTextLayoutGeometry(
      textSpan: controller.buildTextSpan(
        context: capturedContext,
        style: style,
        withComposing: false,
      ),
      width: 520,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
    );
    final visibleLines = _contentLines(geometry);
    final activeBands = geometry.mergedActiveSelectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
      fluidFullLine: true,
    );

    expect(activeBands.length, visibleLines.length);
    for (final box in geometry.selectionRects(
      const TextSelection(baseOffset: 0, extentOffset: raw.length),
    )) {
      expect(
        activeBands.where((band) {
          return _verticalOverlap(band, box) > 0.01 &&
              band.left <= box.left.clamp(0.0, 520.0) + 0.01 &&
              band.right >= box.right.clamp(0.0, 520.0) - 0.01;
        }),
        isNotEmpty,
        reason: 'Rendered-editor selection geometry must cover every visible '
            'Hebrew box while preserving raw offsets for the live TextField.',
      );
    }
  });
}

double _verticalOverlap(Rect a, Rect b) {
  final top = a.top > b.top ? a.top : b.top;
  final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
  return bottom > top ? bottom - top : 0.0;
}

List<ui.LineMetrics> _contentLines(MarkupTextLayoutGeometry geometry) {
  return geometry.painter
      .computeLineMetrics()
      .where((line) => line.width > 0.1)
      .toList(growable: false);
}
