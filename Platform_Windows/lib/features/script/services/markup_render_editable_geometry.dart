part of 'markup_decoration_service.dart';

class MarkupRenderEditableGeometry {
  static List<Rect> selectionRects(
      RenderEditable editable, TextSelection selection,
      {String? rawText}) {
    final normalized = normalizedSelection(
      editable,
      selection,
      rawText: rawText,
    );
    if (normalized == null) return const [];
    return editable
        .getBoxesForSelection(normalized)
        .map((box) => box.toRect())
        .where((rect) => rect.width > 0.5 && rect.height > 1.0)
        .toList(growable: false);
  }

  static List<Rect> mergedBandsForSelection(
    RenderEditable editable,
    TextSelection selection, {
    String? rawText,
    double gapTolerance = MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
  }) {
    return mergedBandsForRects(
      selectionRects(editable, selection, rawText: rawText),
      gapTolerance: gapTolerance,
    );
  }

  static List<Rect> mergedBandsForRects(
    Iterable<Rect> rects, {
    double gapTolerance = MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
  }) {
    return MarkupDecorationBoxMerger.merge(
      rects,
      rowTolerance: 5.0,
      gapTolerance: gapTolerance,
    );
  }

  static Offset? endpointForSelection(
    RenderEditable editable,
    TextSelection selection, {
    String? rawText,
    required bool isRangeStart,
  }) {
    final bands = mergedBandsForSelection(
      editable,
      selection,
      rawText: rawText,
    );
    if (bands.isNotEmpty) {
      return MarkupTextLayoutGeometry.endpointForRects(
        bands,
        isRangeStart: isRangeStart,
        textDirection: editable.textDirection,
      );
    }
    final normalized = normalizedSelection(
      editable,
      selection,
      rawText: rawText,
    );
    if (normalized == null) {
      return _visibleBoundaryCaret(
        editable,
        selection,
        rawText: rawText,
        isRangeStart: isRangeStart,
      );
    }
    final endpoints = editable.getEndpointsForSelection(normalized);
    if (endpoints.isEmpty) return null;
    return (isRangeStart ? endpoints.first : endpoints.last).point;
  }

  static Offset? _visibleBoundaryCaret(
    RenderEditable editable,
    TextSelection selection, {
    required String? rawText,
    required bool isRangeStart,
  }) {
    final textLength = editable.text?.toPlainText().length ?? 0;
    if (textLength <= 0) return null;
    final rawBoundary = isRangeStart ? selection.start : selection.end;
    var caretOffset = rawBoundary.clamp(0, textLength).toInt();
    if (rawText != null && rawText.isNotEmpty) {
      final rawLength = rawText.length.clamp(0, textLength).toInt();
      final visible = MarkupDecorationParser.rawToVisibleOffset(
        rawText,
        caretOffset.clamp(0, rawLength).toInt(),
      );
      caretOffset = MarkupDecorationParser.visibleToRawOffset(rawText, visible)
          .clamp(0, textLength)
          .toInt();
      caretOffset = _visibleToPaintStartRawOffset(rawText, visible)
          .clamp(0, textLength)
          .toInt();
    }
    final rect = editable.getLocalRectForCaret(
      TextPosition(offset: caretOffset, affinity: TextAffinity.downstream),
    );
    return Offset(rect.left, rect.top + rect.height / 2);
  }

  static TextSelection? normalizedSelection(
      RenderEditable editable, TextSelection selection,
      {String? rawText}) {
    if (!selection.isValid || selection.isCollapsed) return null;
    final textLength = editable.text?.toPlainText().length ?? 0;
    if (textLength <= 0) return null;
    var start = selection.start.clamp(0, textLength).toInt();
    var end = selection.end.clamp(start, textLength).toInt();
    if (rawText != null && rawText.isNotEmpty) {
      final rawLength = rawText.length.clamp(0, textLength).toInt();
      final visibleStart = MarkupDecorationParser.rawToVisibleOffset(
        rawText,
        start.clamp(0, rawLength).toInt(),
      );
      final visibleEnd = MarkupDecorationParser.rawToVisibleOffset(
        rawText,
        end.clamp(0, rawLength).toInt(),
      );
      if (visibleEnd <= visibleStart) return null;
      start = _visibleToPaintStartRawOffset(rawText, visibleStart)
          .clamp(0, textLength)
          .toInt();
      end = MarkupDecorationParser.visibleToRawOffset(rawText, visibleEnd)
          .clamp(start, textLength)
          .toInt();
    }
    if (end <= start) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  static int _visibleToPaintStartRawOffset(
    String rawText,
    int visibleOffset,
  ) {
    var raw = MarkupDecorationParser.visibleToRawOffset(rawText, visibleOffset)
        .clamp(0, rawText.length)
        .toInt();
    while (raw < rawText.length) {
      final match = MarkupDecorationParser.tagRegex.matchAsPrefix(rawText, raw);
      if (match == null) break;
      final before = MarkupDecorationParser.rawToVisibleOffset(rawText, raw);
      final after =
          MarkupDecorationParser.rawToVisibleOffset(rawText, match.end);
      if (before != visibleOffset || after != visibleOffset) break;
      raw = match.end;
    }
    return raw;
  }
}
