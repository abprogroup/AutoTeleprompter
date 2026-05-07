import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const bool kUseCustomDocxDecorationPainting = true;
const bool kUseCustomEditorSelectionPainting = true;

enum MarkupDecorationType { background, underline }

class MarkupDecorationRange {
  final MarkupDecorationType type;
  final int start;
  final int end;
  final Color? color;

  const MarkupDecorationRange({
    required this.type,
    required this.start,
    required this.end,
    this.color,
  });

  bool get isValid => end > start;
}

class MarkupDecorationParser {
  static final RegExp tagRegex = RegExp(
    r'\*\*'
    r'|\[\/?u\]'
    r'|\[\/?i\]'
    r'|\[color=([^\]]+)\]|\[\/color\]'
    r'|\[bg=([^\]]+)\]|\[\/bg\]'
    r'|\[size=(\d+(?:\.\d+)?)\]|\[\/size\]'
    r'|\[font=([^\]]+)\]|\[\/font\]'
    r'|\[align=(center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[(center|left|right)\]|\[\/(?:center|left|right)\]'
    r'|\[rtl\]|\[\/rtl\]|\[ltr\]|\[\/ltr\]',
  );

  static List<MarkupDecorationRange> decorationRanges(String rawText) {
    final ranges = <MarkupDecorationRange>[];
    var cursor = 0;
    var underline = false;
    final backgroundStack = <Color>[];

    void emit(int start, int end) {
      if (end <= start) return;
      if (backgroundStack.isNotEmpty) {
        ranges.add(MarkupDecorationRange(
          type: MarkupDecorationType.background,
          start: start,
          end: end,
          color: backgroundStack.last,
        ));
      }
      if (underline) {
        ranges.add(MarkupDecorationRange(
          type: MarkupDecorationType.underline,
          start: start,
          end: end,
        ));
      }
    }

    for (final m in tagRegex.allMatches(rawText)) {
      emit(cursor, m.start);
      final tag = m.group(0)!;
      if (tag == '[u]') {
        underline = true;
      } else if (tag == '[/u]') {
        underline = false;
      } else if (m.group(2) != null) {
        final color = parseHexColor(m.group(2)!);
        if (color != null) backgroundStack.add(color);
      } else if (tag == '[/bg]') {
        if (backgroundStack.isNotEmpty) backgroundStack.removeLast();
      }
      cursor = m.end;
    }
    emit(cursor, rawText.length);
    return ranges.where((range) => range.isValid).toList(growable: false);
  }

  static String visibleText(String rawText) => rawText.replaceAll(tagRegex, '');

  static TextRange? paintableContentRange(
    String rawText,
    MarkupDecorationRange range,
  ) {
    var start = range.start.clamp(0, rawText.length).toInt();
    var end = range.end.clamp(start, rawText.length).toInt();
    while (start < end && _isDecorationWhitespace(rawText.codeUnitAt(start))) {
      start++;
    }
    while (
        end > start && _isDecorationWhitespace(rawText.codeUnitAt(end - 1))) {
      end--;
    }
    if (end <= start) return null;
    return TextRange(start: start, end: end);
  }

  static bool _isDecorationWhitespace(int codeUnit) =>
      codeUnit == 0x09 || // tab
      codeUnit == 0x0A || // line feed
      codeUnit == 0x0D || // carriage return
      codeUnit == 0x20 || // space
      codeUnit == 0xA0; // no-break space

  static int rawToVisibleOffset(String rawText, int rawOffset) {
    final clamped = rawOffset.clamp(0, rawText.length);
    var visible = 0;
    var cursor = 0;
    for (final m in tagRegex.allMatches(rawText)) {
      if (m.start >= clamped) break;
      if (m.start > cursor) {
        visible += (m.start.clamp(0, clamped) - cursor).toInt();
      }
      cursor = m.end;
    }
    if (cursor < clamped) visible += clamped - cursor;
    return visible;
  }

  static int visibleToRawOffset(String rawText, int visibleOffset) {
    final target = visibleOffset < 0 ? 0 : visibleOffset;
    var visible = 0;
    var cursor = 0;
    for (final m in tagRegex.allMatches(rawText)) {
      if (m.start > cursor) {
        final segmentLength = m.start - cursor;
        if (visible + segmentLength >= target) {
          return cursor + target - visible;
        }
        visible += segmentLength;
      }
      cursor = m.end;
    }
    if (cursor < rawText.length) {
      final segmentLength = rawText.length - cursor;
      if (visible + segmentLength >= target) {
        return cursor + target - visible;
      }
    }
    return rawText.length;
  }

  static Color? parseHexColor(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}

class MarkupDecorationBoxMerger {
  static const double styleBackgroundGapTolerance = 28.0;
  static const double styleUnderlineGapTolerance = 14.0;
  static const double activeSelectionGapTolerance = 2.0;

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
  late final List<ui.LineMetrics> _lineMetrics = painter.computeLineMetrics();

  MarkupTextLayoutGeometry({
    required InlineSpan textSpan,
    required this.width,
    required this.textAlign,
    required this.textDirection,
    StrutStyle? strutStyle,
  }) : painter = TextPainter(
          text: textSpan,
          textDirection: textDirection,
          textAlign: textAlign,
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
  }) {
    final boxes = selectionRects(selection);
    return MarkupDecorationBoxMerger.merge(
      boxes,
      rowTolerance: 5.0,
      gapTolerance: type == MarkupDecorationType.background
          ? MarkupDecorationBoxMerger.styleBackgroundGapTolerance
          : MarkupDecorationBoxMerger.styleUnderlineGapTolerance,
    );
  }

  List<Rect> mergedActiveSelectionRects(TextSelection selection) {
    final boxes = selectionRects(selection);
    return MarkupDecorationBoxMerger.merge(
      boxes,
      rowTolerance: 5.0,
      gapTolerance: MarkupDecorationBoxMerger.activeSelectionGapTolerance,
    );
  }

  Rect _alignRectToVisualLine(Rect rect) {
    final line = _nearestLineFor(rect);
    if (line == null) return rect;
    final desiredLeft = _visualLineLeft(line);
    final delta = desiredLeft - line.left;
    if (delta.abs() < 0.01) return rect;
    return rect.shift(Offset(delta, 0));
  }

  ui.LineMetrics? _nearestLineFor(Rect rect) {
    ui.LineMetrics? best;
    var bestDistance = double.infinity;
    final centerY = rect.center.dy;
    for (final line in _lineMetrics) {
      final lineCenter = line.baseline - line.ascent + line.height / 2;
      final distance = (lineCenter - centerY).abs();
      if (distance < bestDistance) {
        best = line;
        bestDistance = distance;
      }
    }
    return best;
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

class MarkupTextDecorationPainter extends CustomPainter {
  final String rawText;
  final InlineSpan textSpan;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final EdgeInsets contentPadding;
  final StrutStyle? strutStyle;
  final MarkupDecorationType type;

  const MarkupTextDecorationPainter({
    required this.rawText,
    required this.textSpan,
    required this.textDirection,
    required this.textAlign,
    required this.type,
    this.contentPadding = EdgeInsets.zero,
    this.strutStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!kUseCustomDocxDecorationPainting || rawText.isEmpty) return;
    final width = size.width - contentPadding.horizontal;
    if (width <= 0) return;

    final geometry = MarkupTextLayoutGeometry(
      textSpan: textSpan,
      width: width,
      textAlign: textAlign,
      textDirection: textDirection,
      strutStyle: strutStyle,
    );

    canvas.save();
    canvas.translate(contentPadding.left, contentPadding.top);
    for (final range in MarkupDecorationParser.decorationRanges(rawText)) {
      if (range.type != type) continue;
      final paintableRange =
          MarkupDecorationParser.paintableContentRange(rawText, range);
      if (paintableRange == null) continue;
      final merged = geometry.mergedDecorationRects(
        TextSelection(
          baseOffset: paintableRange.start,
          extentOffset: paintableRange.end,
        ),
        type: type,
      );
      if (type == MarkupDecorationType.background) {
        _paintBackground(
          canvas,
          merged,
          range.color ?? Colors.transparent,
          width,
        );
      } else {
        _paintUnderline(canvas, merged, width);
      }
    }
    canvas.restore();
  }

  void _paintBackground(
    Canvas canvas,
    List<Rect> rects,
    Color color,
    double width,
  ) {
    if (color.a <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in rects) {
      final band = Rect.fromLTRB(
        (rect.left - 1.5).clamp(0.0, width).toDouble(),
        rect.top,
        (rect.right + 1.5).clamp(0.0, width).toDouble(),
        rect.bottom,
      );
      if (band.width <= 0) continue;
      final radius = Radius.circular((band.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(band, radius), paint);
    }
  }

  void _paintUnderline(Canvas canvas, List<Rect> rects, double width) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final rect in rects) {
      final left = rect.left.clamp(0.0, width).toDouble();
      final right = rect.right.clamp(0.0, width).toDouble();
      if (right <= left) continue;
      final y = rect.bottom - (paint.strokeWidth * 0.5);
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant MarkupTextDecorationPainter oldDelegate) =>
      rawText != oldDelegate.rawText ||
      textSpan != oldDelegate.textSpan ||
      textDirection != oldDelegate.textDirection ||
      textAlign != oldDelegate.textAlign ||
      contentPadding != oldDelegate.contentPadding ||
      strutStyle != oldDelegate.strutStyle ||
      type != oldDelegate.type;
}

class MarkupSelectionDecorationPainter extends CustomPainter {
  final InlineSpan textSpan;
  final TextSelection? selection;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final EdgeInsets contentPadding;
  final StrutStyle? strutStyle;
  final Color color;

  const MarkupSelectionDecorationPainter({
    required this.textSpan,
    required this.selection,
    required this.textDirection,
    required this.textAlign,
    this.contentPadding = EdgeInsets.zero,
    this.strutStyle,
    this.color = const Color(0x66FFBF00),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!kUseCustomEditorSelectionPainting) return;
    final activeSelection = selection;
    if (activeSelection == null ||
        !activeSelection.isValid ||
        activeSelection.isCollapsed) {
      return;
    }

    final width = size.width - contentPadding.horizontal;
    if (width <= 0) return;

    final geometry = MarkupTextLayoutGeometry(
      textSpan: textSpan,
      width: width,
      textAlign: textAlign,
      textDirection: textDirection,
      strutStyle: strutStyle,
    );
    final merged = geometry.mergedActiveSelectionRects(
      TextSelection(
        baseOffset: activeSelection.start,
        extentOffset: activeSelection.end,
      ),
    );
    if (merged.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.save();
    canvas.translate(contentPadding.left, contentPadding.top);
    for (final rect in merged) {
      final band = Rect.fromLTRB(
        rect.left.clamp(0.0, width).toDouble(),
        rect.top,
        rect.right.clamp(0.0, width).toDouble(),
        rect.bottom,
      );
      if (band.width <= 0) continue;
      final radius = Radius.circular((band.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(band, radius), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MarkupSelectionDecorationPainter oldDelegate) =>
      textSpan != oldDelegate.textSpan ||
      selection != oldDelegate.selection ||
      textDirection != oldDelegate.textDirection ||
      textAlign != oldDelegate.textAlign ||
      contentPadding != oldDelegate.contentPadding ||
      strutStyle != oldDelegate.strutStyle ||
      color != oldDelegate.color;
}
