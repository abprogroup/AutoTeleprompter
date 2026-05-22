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
