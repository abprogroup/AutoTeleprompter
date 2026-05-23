import 'dart:ui' as ui;

import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(
    color: Colors.white,
    fontSize: 28,
    height: 1.2,
    letterSpacing: 0,
    wordSpacing: 0,
  );

  testWidgets('RenderEditable bands cover Hebrew wrapped markup selection',
      (tester) async {
    final controller = MarkupController(
      text: '[bg=#806000][u]תקשיבו, אתם במצב לא טוב, אתם כל הזמן רק עסוקים '
          'בלחפש מה לא בסדר אצל השני. אבל איזה מזל גדול שהגעתם לפה הערב, '
          'כי אני לא רק רב מחתן ומוהל חובב, אני גם מחדש נדרים, מה אתם אומרים '
          'שנעשה לכם חידוש קבל עם ואולם?![/u][/bg]',
    );

    await _pumpField(
      tester,
      controller,
      width: 760,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: style,
    );

    final editable = _editable(tester);
    final selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final boxes = MarkupRenderEditableGeometry.selectionRects(
      editable,
      selection,
    );
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      selection,
    );

    expect(boxes, isNotEmpty);
    expect(bands, isNotEmpty);
    for (final box in boxes) {
      expect(
        _coveredBySameRowBand(box, bands),
        isTrue,
        reason: 'RenderEditable box $box was not covered by final bands $bands',
      );
    }
  });

  testWidgets('visible Hebrew search maps back to raw RenderEditable geometry',
      (tester) async {
    final controller = MarkupController(
      text: 'בואו נתקדם בטקס. [bg=#806000]שלב הטבעות[/bg]. '
          'מה זה מ TEMU? מגנוליה?',
    );
    const query = 'בואו נתקדם';

    await _pumpField(
      tester,
      controller,
      width: 500,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: style,
    );

    final visible = MarkupDecorationParser.visibleText(controller.text);
    final visibleStart = visible.indexOf(query);
    expect(visibleStart, isNonNegative);
    final selection = TextSelection(
      baseOffset: MarkupController.visualToRawOffset(
        controller.text,
        visibleStart,
      ),
      extentOffset: MarkupController.visualToRawOffset(
        controller.text,
        visibleStart + query.length,
      ),
    );

    final editable = _editable(tester);
    final boxes = MarkupRenderEditableGeometry.selectionRects(
      editable,
      selection,
    );
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      selection,
    );

    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(_coveredBySameRowBand(box, bands), isTrue);
    }
  });

  testWidgets('hidden markup prefix is not selectable paint', (tester) async {
    const raw = '[bg=#806000][u]\u05d0\u05ea\u05d4 \u05e8\u05e9\u05d0\u05d9 '
        '\u05dc\u05e0\u05e9\u05e0\u05e9 \u05d0\u05ea '
        '\u05d4\u05db\u05dc\u05d4![/u][/bg]';
    final controller = MarkupController(text: raw);

    await _pumpField(
      tester,
      controller,
      width: 760,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: style,
    );

    final editable = _editable(tester);
    final firstVisibleRaw = raw.indexOf('\u05d0\u05ea\u05d4');
    final firstWordAndSpaceRaw = MarkupController.visualToRawOffset(raw, 4);

    expect(
      MarkupRenderEditableGeometry.normalizedSelection(
        editable,
        TextSelection(baseOffset: 0, extentOffset: firstWordAndSpaceRaw),
        rawText: raw,
      )!
          .start,
      firstVisibleRaw,
    );

    expect(
      MarkupRenderEditableGeometry.selectionRects(
        editable,
        TextSelection(baseOffset: 0, extentOffset: firstVisibleRaw),
        rawText: raw,
      ),
      isEmpty,
    );

    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      TextSelection(baseOffset: 0, extentOffset: firstWordAndSpaceRaw),
      rawText: raw,
    );

    expect(bands, isNotEmpty);
    expect(
      bands.map((band) => band.width).reduce((a, b) => a > b ? a : b),
      lessThan(220),
    );
  });

  testWidgets('hidden-only selection endpoint uses visible caret',
      (tester) async {
    const raw = '[bg=#806000][u]\u05d0\u05ea\u05d4 \u05e8\u05e9\u05d0\u05d9 '
        '\u05dc\u05e0\u05e9\u05e0\u05e9 \u05d0\u05ea '
        '\u05d4\u05db\u05dc\u05d4![/u][/bg]';
    final controller = MarkupController(text: raw);

    await _pumpField(
      tester,
      controller,
      width: 760,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: style,
    );

    final editable = _editable(tester);
    final firstVisibleRaw = raw.indexOf('\u05d0\u05ea\u05d4');
    final endpoint = MarkupRenderEditableGeometry.endpointForSelection(
      editable,
      TextSelection(baseOffset: 0, extentOffset: firstVisibleRaw),
      rawText: raw,
      isRangeStart: false,
    );
    final caret = editable.getLocalRectForCaret(
      TextPosition(
        offset: firstVisibleRaw,
        affinity: TextAffinity.downstream,
      ),
    );
    final expected = Offset(caret.left, caret.top + caret.height / 2);

    expect(endpoint, isNotNull);
    expect(endpoint!.dx, closeTo(expected.dx, 0.1));
    expect(endpoint.dy, closeTo(expected.dy, 0.1));
  });

  testWidgets('single Hebrew visible step after hidden tags stays tight',
      (tester) async {
    const raw = '[bg=#806000][u]\u05d0\u05ea\u05d4 \u05e8\u05e9\u05d0\u05d9 '
        '\u05dc\u05e0\u05e9\u05e0\u05e9 \u05d0\u05ea '
        '\u05d4\u05db\u05dc\u05d4![/u][/bg]';
    final controller = MarkupController(text: raw);

    await _pumpField(
      tester,
      controller,
      width: 760,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      style: style,
    );

    final visible = MarkupDecorationParser.visibleText(raw);
    final visibleSeed = visible.indexOf('\u05dc\u05e0\u05e9\u05e0\u05e9');
    expect(visibleSeed, isNonNegative);

    final selection = TextSelection(
      baseOffset: MarkupController.visualToRawOffset(raw, visibleSeed),
      extentOffset: MarkupController.visualToRawOffset(raw, visibleSeed + 1),
    );
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      _editable(tester),
      selection,
      rawText: raw,
    );

    expect(bands, isNotEmpty);
    expect(
      bands.map((band) => band.width).reduce((a, b) => a > b ? a : b),
      lessThan(120),
      reason: 'One visible caret step must not paint as a full RTL row.',
    );
  });

  testWidgets('single English visible step after hidden tags stays tight',
      (tester) async {
    const raw = '[bg=#806000][u]hello world from markup[/u][/bg]';
    final controller = MarkupController(text: raw);

    await _pumpField(
      tester,
      controller,
      width: 620,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      style: style,
    );

    final visible = MarkupDecorationParser.visibleText(raw);
    final visibleSeed = visible.indexOf('world');
    expect(visibleSeed, isNonNegative);

    final selection = TextSelection(
      baseOffset: MarkupController.visualToRawOffset(raw, visibleSeed),
      extentOffset: MarkupController.visualToRawOffset(raw, visibleSeed + 1),
    );
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      _editable(tester),
      selection,
      rawText: raw,
    );

    expect(bands, isNotEmpty);
    expect(
      bands.map((band) => band.width).reduce((a, b) => a > b ? a : b),
      lessThan(80),
      reason: 'One visible caret step must not paint as a full LTR row.',
    );
  });

  testWidgets('RenderEditable bands cover English wrapped markup selection',
      (tester) async {
    final controller = MarkupController(
      text:
          '[bg=#806000]These women are here for a reason. Their stories teach '
          'us powerful truth about the character of God our father. He sees '
          'you and deeply cares for you.[/bg]',
    );

    await _pumpField(
      tester,
      controller,
      width: 620,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      style: style,
    );

    final editable = _editable(tester);
    final selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
    final boxes = MarkupRenderEditableGeometry.selectionRects(
      editable,
      selection,
    );
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      selection,
    );

    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(_coveredBySameRowBand(box, bands), isTrue);
    }
  });
}

Future<void> _pumpField(
  WidgetTester tester,
  MarkupController controller, {
  required double width,
  required TextDirection textDirection,
  required TextAlign textAlign,
  required TextStyle style,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: TextField(
              controller: controller,
              maxLines: null,
              textDirection: textDirection,
              textAlign: textAlign,
              selectionWidthStyle: ui.BoxWidthStyle.tight,
              style: style,
              strutStyle: const StrutStyle(
                fontSize: 28,
                height: 1.2,
                forceStrutHeight: true,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 2),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RenderEditable _editable(WidgetTester tester) {
  final root = tester.renderObject(find.byType(EditableText));
  final editable = _findRenderEditable(root);
  if (editable == null) {
    throw StateError('RenderEditable not found below EditableText');
  }
  return editable;
}

bool _coveredBySameRowBand(Rect box, List<Rect> bands) {
  return bands.any((band) {
    final sameRow = (band.center.dy - box.center.dy).abs() <=
        5.0 + (band.height + box.height) * 0.08;
    return sameRow &&
        band.left <= box.left + 0.5 &&
        band.right >= box.right - 0.5;
  });
}

RenderEditable? _findRenderEditable(RenderObject root) {
  if (root is RenderEditable) return root;
  RenderEditable? result;
  root.visitChildren((child) {
    result ??= _findRenderEditable(child);
  });
  return result;
}
