part of 'global_selection_overlay.dart';

class _EditorHighlightOverlayPainter extends CustomPainter {
  final GlobalKey stackKey;
  final List<MarkupController> controllers;
  final List<GlobalKey> blockKeys;
  final bool highlightBackgroundsAsText;

  _EditorHighlightOverlayPainter({
    required this.stackKey,
    required this.controllers,
    required this.blockKeys,
    required this.highlightBackgroundsAsText,
    Listenable? repaint,
  }) : super(
          repaint: Listenable.merge([
            ...controllers,
            if (repaint != null) repaint,
          ]),
        );

  @override
  void paint(Canvas canvas, Size size) {
    final stackBox = stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.attached) return;

    final styleBandsByColor = <Color, List<Rect>>{};
    final selectionBands = <Rect>[];
    final underlineBands = <Rect>[];
    final blockCount = controllers.length < blockKeys.length
        ? controllers.length
        : blockKeys.length;

    for (var index = 0; index < blockCount; index++) {
      final renderObject = blockKeys[index].currentContext?.findRenderObject();
      if (renderObject == null) continue;
      final editable = _findRenderEditable(renderObject);
      if (editable == null || !editable.attached) continue;

      final controller = controllers[index];
      final rawText = controller.text;
      if (kUseCustomDocxDecorationPainting && rawText.isNotEmpty) {
        if (!highlightBackgroundsAsText) {
          for (final run in _backgroundPaintRuns(rawText)) {
            final bands = _localPaintBands(
              editable,
              TextSelection(
                baseOffset: run.range.start,
                extentOffset: run.range.end,
              ),
              rawText,
              applyBackgroundTail: true,
            );
            if (bands.isEmpty) continue;
            styleBandsByColor
                .putIfAbsent(run.color, () => <Rect>[])
                .addAll(_toStackRects(editable, stackBox, bands));
          }
        }
        for (final range in MarkupDecorationParser.decorationRanges(rawText)) {
          if (range.type != MarkupDecorationType.underline) continue;
          final paintable = MarkupDecorationParser.paintableContentRange(
            rawText,
            range,
          );
          if (paintable == null) continue;
          final bands = _localUnderlineBands(
            editable,
            TextSelection(
              baseOffset: paintable.start,
              extentOffset: paintable.end,
            ),
            rawText,
          );
          underlineBands.addAll(_toStackRects(editable, stackBox, bands));
        }
      }

      if (kUseCustomEditorSelectionPainting) {
        final selection = _activeSelectionForBlock(controller);
        if (selection != null) {
          final bands = _localPaintBands(
            editable,
            selection,
            rawText,
            applyBackgroundTail: false,
          );
          selectionBands.addAll(_toStackRects(editable, stackBox, bands));
        }
      }
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final entry in styleBandsByColor.entries) {
      HighlightBandPainter.paintConnectedRegion(
        canvas,
        entry.value,
        entry.key,
        size,
        radius: HighlightBandPainter.suggestedRadius(entry.value),
      );
    }
    HighlightBandPainter.paintConnectedRegion(
      canvas,
      selectionBands,
      const Color(0x66FFBF00),
      size,
      radius: HighlightBandPainter.suggestedRadius(selectionBands),
    );
    _paintUnderlineBands(canvas, underlineBands, size);
    canvas.restore();
  }

  void _paintUnderlineBands(Canvas canvas, List<Rect> bands, Size size) {
    if (bands.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final rect in bands) {
      final left = rect.left.clamp(0.0, size.width).toDouble();
      final right = rect.right.clamp(0.0, size.width).toDouble();
      if (right <= left) continue;
      final y = rect.bottom.clamp(0.0, size.height).toDouble() -
          paint.strokeWidth * 0.5;
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  List<Rect> _localPaintBands(
    RenderEditable editable,
    TextSelection selection,
    String rawText, {
    required bool applyBackgroundTail,
  }) {
    if (!selection.isValid || selection.isCollapsed) return const [];
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      selection,
      rawText: rawText,
      gapTolerance: applyBackgroundTail
          ? _styleBackgroundGapTolerance(editable)
          : MarkupDecorationBoxMerger.activeSelectionGapTolerance,
    );
    if (bands.isEmpty) return const [];
    final lanes = HighlightBandPainter.textLaneBands(
      bands,
      editable.size,
      topPaddingRatio: applyBackgroundTail ? 0.02 : 0.02,
      bottomPaddingRatio: applyBackgroundTail ? 0.24 : 0.14,
      minHeight: applyBackgroundTail ? 8.0 : 6.0,
      maxHeight: applyBackgroundTail ? 200.0 : 160.0,
    );
    return [
      for (final lane in lanes)
        _withHorizontalTails(
          editable,
          lane,
          applyBackgroundTail: applyBackgroundTail,
        ),
    ];
  }

  Rect _withHorizontalTails(
    RenderEditable editable,
    Rect rect, {
    required bool applyBackgroundTail,
  }) {
    if (!applyBackgroundTail) {
      return Rect.fromLTRB(
        rect.left.clamp(0.0, editable.size.width).toDouble().floorToDouble(),
        rect.top.clamp(0.0, editable.size.height).toDouble().floorToDouble(),
        rect.right.clamp(0.0, editable.size.width).toDouble().ceilToDouble(),
        rect.bottom.clamp(0.0, editable.size.height).toDouble().ceilToDouble(),
      );
    }
    final isRtl = editable.textDirection == TextDirection.rtl;
    final leftTail = isRtl
        ? MarkupDecorationBoxMerger.styleBackgroundVisualEndTail
        : MarkupDecorationBoxMerger.styleBackgroundInnerTail;
    final rightTail = isRtl
        ? MarkupDecorationBoxMerger.styleBackgroundInnerTail
        : MarkupDecorationBoxMerger.styleBackgroundVisualEndTail;
    return Rect.fromLTRB(
      (rect.left - leftTail)
          .clamp(0.0, editable.size.width)
          .toDouble()
          .floorToDouble(),
      rect.top.clamp(0.0, editable.size.height).toDouble().floorToDouble(),
      (rect.right + rightTail)
          .clamp(0.0, editable.size.width)
          .toDouble()
          .ceilToDouble(),
      rect.bottom.clamp(0.0, editable.size.height).toDouble().ceilToDouble(),
    );
  }

  List<Rect> _localUnderlineBands(
    RenderEditable editable,
    TextSelection selection,
    String rawText,
  ) {
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      selection,
      rawText: rawText,
      gapTolerance: MarkupDecorationBoxMerger.styleUnderlineGapTolerance,
    );
    if (bands.isEmpty) return const [];
    final isRtl = editable.textDirection == TextDirection.rtl;
    final leftTail =
        isRtl ? MarkupDecorationBoxMerger.styleUnderlineVisualEndTail : 0.0;
    final rightTail =
        isRtl ? 0.0 : MarkupDecorationBoxMerger.styleUnderlineVisualEndTail;
    return [
      for (final rect in bands)
        Rect.fromLTRB(
          (rect.left - leftTail).clamp(0.0, editable.size.width).toDouble(),
          rect.top.clamp(0.0, editable.size.height).toDouble(),
          (rect.right + rightTail).clamp(0.0, editable.size.width).toDouble(),
          rect.bottom.clamp(0.0, editable.size.height).toDouble(),
        ),
    ].where((rect) => rect.width > 0 && rect.height > 0).toList();
  }

  List<Rect> _toStackRects(
    RenderEditable editable,
    RenderBox stackBox,
    List<Rect> localRects,
  ) {
    return [
      for (final rect in localRects)
        Rect.fromPoints(
          editable.localToGlobal(rect.topLeft, ancestor: stackBox),
          editable.localToGlobal(rect.bottomRight, ancestor: stackBox),
        ),
    ].where((rect) => rect.width > 0 && rect.height > 0).toList();
  }

  TextSelection? _activeSelectionForBlock(MarkupController controller) {
    final length = controller.text.length;
    if (length <= 0) return null;
    TextSelection? selection;
    if (controller.isGlobalSelected) {
      selection = TextSelection(baseOffset: 0, extentOffset: length);
    } else {
      final external = controller.externalSelection;
      if (external == null || !external.isValid || external.isCollapsed) {
        return null;
      }
      selection = external;
    }
    final start = selection.start.clamp(0, length).toInt();
    final end = selection.end.clamp(start, length).toInt();
    if (end <= start) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  List<_EditorHighlightRun> _backgroundPaintRuns(String rawText) {
    final runs = <_EditorHighlightRun>[];
    Color? pendingColor;
    TextRange? pendingRange;

    void flush() {
      final range = pendingRange;
      final color = pendingColor;
      if (range != null && color != null && range.end > range.start) {
        runs.add(_EditorHighlightRun(range: range, color: color));
      }
      pendingColor = null;
      pendingRange = null;
    }

    for (final range in MarkupDecorationParser.decorationRanges(rawText)) {
      if (range.type != MarkupDecorationType.background) continue;
      final paintable = MarkupDecorationParser.paintableContentRange(
        rawText,
        range,
      );
      final color = range.color;
      if (paintable == null || color == null) continue;
      final canJoin = pendingColor == color &&
          pendingRange != null &&
          _visibleGapIsWhitespace(rawText, pendingRange!.end, paintable.start);
      if (canJoin) {
        pendingRange = TextRange(
          start: pendingRange!.start,
          end: paintable.end,
        );
      } else {
        flush();
        pendingColor = color;
        pendingRange = paintable;
      }
    }
    flush();
    return runs;
  }

  bool _visibleGapIsWhitespace(String rawText, int start, int end) {
    if (end <= start) return true;
    final safeStart = start.clamp(0, rawText.length).toInt();
    final safeEnd = end.clamp(safeStart, rawText.length).toInt();
    final visibleGap = MarkupDecorationParser.visibleText(
      rawText.substring(safeStart, safeEnd),
    );
    return visibleGap.trim().isEmpty;
  }

  double _styleBackgroundGapTolerance(RenderEditable editable) {
    final dynamicGap = editable.preferredLineHeight * 0.75;
    return dynamicGap > MarkupDecorationBoxMerger.styleBackgroundGapTolerance
        ? dynamicGap
        : MarkupDecorationBoxMerger.styleBackgroundGapTolerance;
  }

  @override
  bool shouldRepaint(covariant _EditorHighlightOverlayPainter oldDelegate) {
    return oldDelegate.controllers != controllers ||
        oldDelegate.blockKeys != blockKeys ||
        oldDelegate.stackKey != stackKey ||
        oldDelegate.highlightBackgroundsAsText != highlightBackgroundsAsText;
  }
}

class _EditorHighlightRun {
  final TextRange range;
  final Color color;

  const _EditorHighlightRun({
    required this.range,
    required this.color,
  });
}
