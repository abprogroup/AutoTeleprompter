import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

part 'markup_decoration_parser.dart';
part 'markup_render_editable_geometry.dart';

const bool kUseCustomDocxDecorationPainting = true;
const bool kUseCustomEditorSelectionPainting = true;

class MarkupDecorationBoxMerger {
  static const double styleBackgroundGapTolerance = 28.0;
  static const double styleUnderlineGapTolerance = 14.0;
  static const double activeSelectionGapTolerance = 2.0;
  static const double styleBackgroundInnerTail = 2.0;
  static const double styleBackgroundVisualEndTail = 6.0;
  static const double styleUnderlineVisualEndTail = 3.0;

  static List<Rect> merge(
    Iterable<Rect> boxes, {
    double rowTolerance = 4.0,
    double gapTolerance = 10.0,
  }) {
    final sorted = boxes.where((box) => !box.isEmpty).toList()
      ..sort((a, b) {
        final topCompare = a.center.dy.compareTo(b.center.dy);
        if (topCompare != 0 &&
            (a.center.dy - b.center.dy).abs() > rowTolerance) {
          return topCompare;
        }
        return a.left.compareTo(b.left);
      });

    final merged = <Rect>[];
    for (final box in sorted) {
      if (merged.isEmpty) {
        merged.add(box);
        continue;
      }
      final last = merged.last;
      final sameRow = (last.center.dy - box.center.dy).abs() <=
          rowTolerance + (last.height + box.height) * 0.08;
      final closeEnough = box.left <= last.right + gapTolerance;
      if (sameRow && closeEnough) {
        merged[merged.length - 1] = Rect.fromLTRB(
          last.left < box.left ? last.left : box.left,
          last.top < box.top ? last.top : box.top,
          last.right > box.right ? last.right : box.right,
          last.bottom > box.bottom ? last.bottom : box.bottom,
        );
      } else {
        merged.add(box);
      }
    }
    return merged;
  }
}

class MarkupTextLayoutGeometry {
  final TextPainter painter;
  final double width;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  late final List<ui.LineMetrics> _lineMetrics = painter.computeLineMetrics();

  MarkupTextLayoutGeometry({
    required InlineSpan textSpan,
    required this.width,
    required this.textAlign,
    required this.textDirection,
    this.textScaler = TextScaler.noScaling,
    StrutStyle? strutStyle,
  }) : painter = TextPainter(
          text: textSpan,
          textDirection: textDirection,
          textAlign: textAlign,
          textScaler: textScaler,
          strutStyle: strutStyle,
        )..layout(maxWidth: width);

  List<Rect> selectionRects(
    TextSelection selection, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
    ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight,
    bool alignToVisualLine = true,
  }) {
    return painter
        .getBoxesForSelection(
          selection,
          boxHeightStyle: boxHeightStyle,
          boxWidthStyle: boxWidthStyle,
        )
        .map((box) => alignToVisualLine
            ? _alignRectToVisualLine(box.toRect())
            : box.toRect())
        .where((rect) => !rect.isEmpty)
        .toList(growable: false);
  }

  List<Rect> mergedDecorationRects(
    TextSelection selection, {
    required MarkupDecorationType type,
    List<TextSelection>? unitSelections,
  }) {
    final boxes = _rectsForSelectionUnits(
      unitSelections,
      fallbackSelection: selection,
    );
    final gapTolerance = type == MarkupDecorationType.background
        ? MarkupDecorationBoxMerger.styleBackgroundGapTolerance
        : MarkupDecorationBoxMerger.styleUnderlineGapTolerance;
    final grouped = _boxesByVisualLine(boxes);
    if (grouped.isEmpty) return const [];
    final indexes = grouped.keys.toList()..sort();
    return [
      for (final index in indexes)
        ...MarkupDecorationBoxMerger.merge(
          grouped[index]!,
          rowTolerance: 5.0,
          gapTolerance: gapTolerance,
        ),
    ];
  }

  List<Rect> mergedActiveSelectionRects(
    TextSelection selection, {
    List<TextSelection>? unitSelections,
    bool fluidFullLine = false,
  }) {
    if (fluidFullLine) {
      final ownershipBoxes = _rectsForSelectionUnits(
        unitSelections,
        fallbackSelection: selection,
      );
      return _activeSelectionLineBands(ownershipBoxes, selection);
    }
    final boxes = _rectsForSelectionUnits(
      unitSelections,
      fallbackSelection: selection,
      boxHeightStyle: ui.BoxHeightStyle.strut,
    );
    return MarkupDecorationBoxMerger.merge(
      boxes,
      rowTolerance: 5.0,
      gapTolerance: MarkupDecorationBoxMerger.activeSelectionGapTolerance,
    );
  }

  List<Rect> _activeSelectionLineBands(
    List<Rect> boxes,
    TextSelection selection,
  ) {
    final nonEmpty = boxes.where((box) => !box.isEmpty).toList();
    if (nonEmpty.isEmpty || _lineMetrics.isEmpty) return const [];
    final textLength = painter.text?.toPlainText().length ?? 0;
    final fullSelection =
        selection.start <= 0 && textLength > 0 && selection.end >= textLength;
    final buckets = <int, Rect>{};
    for (final box in nonEmpty) {
      final lineIndex = _overlappingLineIndexFor(box);
      if (lineIndex == null) continue;
      final current = buckets[lineIndex];
      buckets[lineIndex] = current == null ? box : current.expandToInclude(box);
    }
    if (buckets.isEmpty) return const [];

    final indexes = buckets.keys.toList()..sort();
    final rows = <Rect>[];
    for (final index in indexes) {
      final line = _lineMetrics[index];
      final top = line.baseline - line.ascent;
      final bottom = top + line.height;
      final selected = buckets[index]!;
      final lineLeft = _visualLineLeft(line);
      final lineRight = (lineLeft + line.width).clamp(0.0, width).toDouble();
      final left = fullSelection
          ? (selected.left < lineLeft ? selected.left : lineLeft)
          : selected.left;
      final right = fullSelection
          ? (selected.right > lineRight ? selected.right : lineRight)
          : selected.right;
      rows.add(Rect.fromLTRB(
        left.clamp(0.0, width).toDouble(),
        top,
        right.clamp(0.0, width).toDouble(),
        bottom,
      ));
    }
    return rows.where((row) => row.width > 0 && row.height > 0).toList();
  }

  List<Rect> _rectsForSelectionUnits(
    List<TextSelection>? unitSelections, {
    required TextSelection fallbackSelection,
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
  }) {
    final units = unitSelections ?? const <TextSelection>[];
    if (units.isEmpty) {
      return selectionRects(
        fallbackSelection,
        boxHeightStyle: boxHeightStyle,
      );
    }
    return [
      for (final unit in units)
        ...selectionRects(
          unit,
          boxHeightStyle: boxHeightStyle,
        ),
    ];
  }

  Map<int, List<Rect>> _boxesByVisualLine(List<Rect> boxes) {
    final grouped = <int, List<Rect>>{};
    for (final box in boxes.where((box) => !box.isEmpty)) {
      final lineIndex = _overlappingLineIndexFor(box);
      if (lineIndex == null) continue;
      grouped.putIfAbsent(lineIndex, () => <Rect>[]).add(box);
    }
    return grouped;
  }

  Offset? activeSelectionEndpoint(
    TextSelection selection, {
    required bool isRangeStart,
  }) {
    final rects = mergedActiveSelectionRects(
      selection,
      fluidFullLine: true,
    );
    if (rects.isEmpty) return null;
    return endpointForRects(
      rects,
      isRangeStart: isRangeStart,
      textDirection: textDirection,
    );
  }

  static Offset endpointForRects(
    List<Rect> rects, {
    required bool isRangeStart,
    required TextDirection textDirection,
  }) {
    const lineTolerance = 4.0;
    final sorted = rects.where((rect) => !rect.isEmpty).toList()
      ..sort((a, b) {
        final yCompare = a.center.dy.compareTo(b.center.dy);
        if (yCompare != 0 &&
            (a.center.dy - b.center.dy).abs() > lineTolerance) {
          return yCompare;
        }
        return a.left.compareTo(b.left);
      });
    if (sorted.isEmpty) return Offset.zero;

    final targetY =
        isRangeStart ? sorted.first.center.dy : sorted.last.center.dy;
    final sameLine = sorted
        .where((rect) => (rect.center.dy - targetY).abs() <= lineTolerance)
        .toList();
    final lineRects = sameLine.isEmpty ? sorted : sameLine;
    final rtl = textDirection == TextDirection.rtl;
    final x = rtl
        ? isRangeStart
            ? lineRects
                .map((rect) => rect.right)
                .reduce((a, b) => a > b ? a : b)
            : lineRects.map((rect) => rect.left).reduce((a, b) => a < b ? a : b)
        : isRangeStart
            ? lineRects.map((rect) => rect.left).reduce((a, b) => a < b ? a : b)
            : lineRects
                .map((rect) => rect.right)
                .reduce((a, b) => a > b ? a : b);
    return Offset(x, targetY);
  }

  Rect _alignRectToVisualLine(Rect rect) {
    final lineIndex = _overlappingLineIndexFor(rect);
    if (lineIndex == null) return rect;
    final line = _lineMetrics[lineIndex];
    final desiredLeft = _visualLineLeft(line);
    final delta = desiredLeft - line.left;
    if (delta.abs() < 0.01) return rect;
    final desiredRight = desiredLeft + line.width;
    final alreadyInVisualLine =
        rect.left >= desiredLeft - 1.0 && rect.right <= desiredRight + 1.0;
    if (alreadyInVisualLine) return rect;
    return rect.shift(Offset(delta, 0));
  }

  int? _nearestLineIndexFor(Rect rect) {
    ui.LineMetrics? best;
    int? bestIndex;
    var bestDistance = double.infinity;
    final centerY = rect.center.dy;
    for (var i = 0; i < _lineMetrics.length; i++) {
      final line = _lineMetrics[i];
      final lineCenter = line.baseline - line.ascent + line.height / 2;
      final distance = (lineCenter - centerY).abs();
      if (distance < bestDistance) {
        best = line;
        bestIndex = i;
        bestDistance = distance;
      }
    }
    return best == null ? null : bestIndex;
  }

  int? _overlappingLineIndexFor(Rect rect) {
    int? bestIndex;
    var bestOverlap = 0.0;
    var bestCenterDistance = double.infinity;
    final centerY = rect.center.dy;
    for (var i = 0; i < _lineMetrics.length; i++) {
      final line = _lineMetrics[i];
      final top = line.baseline - line.ascent;
      final bottom = top + line.height;
      final overlap = (rect.bottom < top || rect.top > bottom)
          ? 0.0
          : (rect.bottom < bottom ? rect.bottom : bottom) -
              (rect.top > top ? rect.top : top);
      final lineCenter = top + line.height / 2;
      final centerDistance = (lineCenter - centerY).abs();
      final winsByOverlap = overlap > bestOverlap + 0.01;
      final winsTie = (overlap - bestOverlap).abs() <= 0.01 &&
          centerDistance < bestCenterDistance;
      if (winsByOverlap || winsTie) {
        bestIndex = i;
        bestOverlap = overlap;
        bestCenterDistance = centerDistance;
      }
    }
    if (bestIndex != null && bestOverlap > 0.01) return bestIndex;
    return _nearestLineIndexFor(rect);
  }

  double _visualLineLeft(ui.LineMetrics line) {
    final left = switch (textAlign) {
      TextAlign.left => 0.0,
      TextAlign.right => width - line.width,
      TextAlign.center => (width - line.width) / 2,
      TextAlign.start =>
        textDirection == TextDirection.rtl ? width - line.width : 0.0,
      TextAlign.end =>
        textDirection == TextDirection.rtl ? 0.0 : width - line.width,
      TextAlign.justify => 0.0,
    };
    return left.clamp(0.0, width).toDouble();
  }
}
