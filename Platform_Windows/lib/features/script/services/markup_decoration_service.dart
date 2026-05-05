import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const bool kUseCustomDocxDecorationPainting = true;

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

    final visible = MarkupDecorationParser.visibleText(rawText);
    if (visible.isEmpty) return;
    final rootStyle =
        textSpan is TextSpan ? (textSpan as TextSpan).style : null;
    final painter = TextPainter(
      text: TextSpan(text: visible, style: rootStyle),
      textDirection: textDirection,
      textAlign: textAlign,
      strutStyle: strutStyle,
    )..layout(maxWidth: width);

    canvas.save();
    canvas.translate(contentPadding.left, contentPadding.top);
    for (final range in MarkupDecorationParser.decorationRanges(rawText)) {
      if (range.type != type) continue;
      final start = MarkupDecorationParser.rawToVisibleOffset(
        rawText,
        range.start,
      );
      final end = MarkupDecorationParser.rawToVisibleOffset(
        rawText,
        range.end,
      );
      if (end <= start) continue;
      final boxes = painter
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
            boxHeightStyle: ui.BoxHeightStyle.tight,
            boxWidthStyle: ui.BoxWidthStyle.tight,
          )
          .map((box) => box.toRect());
      final merged = MarkupDecorationBoxMerger.merge(
        boxes,
        rowTolerance: 5.0,
        gapTolerance: 12.0,
      );
      if (type == MarkupDecorationType.background) {
        _paintBackground(canvas, merged, range.color ?? Colors.transparent);
      } else {
        _paintUnderline(canvas, merged);
      }
    }
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, List<Rect> rects, Color color) {
    if (color.a <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in rects) {
      final radius = Radius.circular((rect.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
    }
  }

  void _paintUnderline(Canvas canvas, List<Rect> rects) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final rect in rects) {
      final y = rect.bottom - (paint.strokeWidth * 0.5);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
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
