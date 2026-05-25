part of 'script_editor_screen.dart';

class _EditorRenderEditableDecorations extends SingleChildRenderObjectWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextSelection? selection;
  final TextDirection textDirection;

  const _EditorRenderEditableDecorations({
    required this.controller,
    required this.focusNode,
    required this.selection,
    required this.textDirection,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEditorRenderEditableDecorations(
      controller: controller,
      focusNode: focusNode,
      selection: selection,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderEditorRenderEditableDecorations renderObject,
  ) {
    renderObject
      ..controller = controller
      ..focusNode = focusNode
      ..selection = selection
      ..textDirection = textDirection;
  }
}

class _RenderEditorRenderEditableDecorations extends RenderProxyBox {
  TextEditingController _controller;
  FocusNode _focusNode;
  TextSelection? _selection;
  TextDirection _textDirection;
  bool _listeningToController = false;
  bool _listeningToFocus = false;

  _RenderEditorRenderEditableDecorations({
    required TextEditingController controller,
    required FocusNode focusNode,
    required TextSelection? selection,
    required TextDirection textDirection,
  })  : _controller = controller,
        _focusNode = focusNode,
        _selection = selection,
        _textDirection = textDirection;

  String get _rawText => _controller.text;

  set controller(TextEditingController value) {
    if (identical(value, _controller)) return;
    _stopControllerListener();
    _controller = value;
    _startControllerListener();
    markNeedsPaint();
  }

  set focusNode(FocusNode value) {
    if (identical(value, _focusNode)) return;
    _stopFocusListener();
    _focusNode = value;
    _startFocusListener();
    markNeedsPaint();
  }

  set selection(TextSelection? value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _startControllerListener();
    _startFocusListener();
  }

  @override
  void detach() {
    _stopFocusListener();
    _stopControllerListener();
    super.detach();
  }

  void _startControllerListener() {
    if (_listeningToController) return;
    _controller.addListener(_handleControllerChanged);
    _listeningToController = true;
  }

  void _stopControllerListener() {
    if (!_listeningToController) return;
    _controller.removeListener(_handleControllerChanged);
    _listeningToController = false;
  }

  void _handleControllerChanged() {
    markNeedsPaint();
  }

  void _startFocusListener() {
    if (_listeningToFocus) return;
    _focusNode.addListener(_handleFocusChanged);
    _listeningToFocus = true;
  }

  void _stopFocusListener() {
    if (!_listeningToFocus) return;
    _focusNode.removeListener(_handleFocusChanged);
    _listeningToFocus = false;
  }

  void _handleFocusChanged() {
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final editable = _findRenderEditable(child);
    if (editable == null) {
      super.paint(context, offset);
      return;
    }

    final editableOffset = editable.localToGlobal(Offset.zero, ancestor: this);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(
        offset.dx + editableOffset.dx, offset.dy + editableOffset.dy);
    _paintStyleBackgrounds(canvas, editable);
    _paintActiveSelection(canvas, editable);
    canvas.restore();

    super.paint(context, offset);

    canvas.save();
    canvas.translate(
        offset.dx + editableOffset.dx, offset.dy + editableOffset.dy);
    _paintUnderlines(canvas, editable);
    canvas.restore();
  }

  RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  void _paintStyleBackgrounds(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomDocxDecorationPainting || _rawText.isEmpty) return;
    for (final run in _backgroundPaintRuns()) {
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(
          baseOffset: run.range.start,
          extentOffset: run.range.end,
        ),
        rawText: _rawText,
        gapTolerance: _styleBackgroundGapTolerance(editable),
      );
      _paintBands(
        canvas,
        editable,
        bands,
        run.color,
        applyBackgroundTail: true,
      );
    }
  }

  List<_BackgroundPaintRun> _backgroundPaintRuns() {
    final runs = <_BackgroundPaintRun>[];
    Color? pendingColor;
    TextRange? pendingRange;

    void flush() {
      final range = pendingRange;
      final color = pendingColor;
      if (range != null && color != null && range.end > range.start) {
        runs.add(_BackgroundPaintRun(range: range, color: color));
      }
      pendingColor = null;
      pendingRange = null;
    }

    for (final range in MarkupDecorationParser.decorationRanges(_rawText)) {
      if (range.type != MarkupDecorationType.background) continue;
      final paintable = MarkupDecorationParser.paintableContentRange(
        _rawText,
        range,
      );
      final color = range.color;
      if (paintable == null || color == null) continue;
      final canJoin = pendingColor == color &&
          pendingRange != null &&
          _visibleGapIsWhitespace(pendingRange!.end, paintable.start);
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

  bool _visibleGapIsWhitespace(int start, int end) {
    if (end <= start) return true;
    final safeStart = start.clamp(0, _rawText.length).toInt();
    final safeEnd = end.clamp(safeStart, _rawText.length).toInt();
    final visibleGap = MarkupDecorationParser.visibleText(
      _rawText.substring(safeStart, safeEnd),
    );
    return visibleGap.trim().isEmpty;
  }

  double _styleBackgroundGapTolerance(RenderEditable editable) {
    final dynamicGap = editable.preferredLineHeight * 0.75;
    return dynamicGap > MarkupDecorationBoxMerger.styleBackgroundGapTolerance
        ? dynamicGap
        : MarkupDecorationBoxMerger.styleBackgroundGapTolerance;
  }

  void _paintActiveSelection(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomEditorSelectionPainting) return;
    final activeSelection = _activePaintSelection();
    if (activeSelection == null ||
        !activeSelection.isValid ||
        activeSelection.isCollapsed) {
      return;
    }
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      activeSelection,
      rawText: _rawText,
      gapTolerance: MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
    );
    _paintBands(
      canvas,
      editable,
      bands,
      const Color(0x66FFBF00),
      applyBackgroundTail: false,
    );
  }

  TextSelection? _activePaintSelection() {
    final appSelection = _selection;
    if (appSelection != null &&
        appSelection.isValid &&
        !appSelection.isCollapsed) {
      return appSelection;
    }
    if (!_focusNode.hasFocus) return null;
    final native = _controller.selection;
    return native.isValid && !native.isCollapsed ? native : null;
  }

  void _paintUnderlines(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomDocxDecorationPainting || _rawText.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final range in MarkupDecorationParser.decorationRanges(_rawText)) {
      if (range.type != MarkupDecorationType.underline) continue;
      final paintable = MarkupDecorationParser.paintableContentRange(
        _rawText,
        range,
      );
      if (paintable == null) continue;
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(
          baseOffset: paintable.start,
          extentOffset: paintable.end,
        ),
        rawText: _rawText,
        gapTolerance: MarkupDecorationBoxMerger.styleUnderlineGapTolerance,
      );
      for (final rect in bands) {
        final leftTail = _textDirection == TextDirection.rtl
            ? MarkupDecorationBoxMerger.styleUnderlineVisualEndTail
            : 0.0;
        final rightTail = _textDirection == TextDirection.rtl
            ? 0.0
            : MarkupDecorationBoxMerger.styleUnderlineVisualEndTail;
        final left = (rect.left - leftTail).clamp(0.0, editable.size.width);
        final right = (rect.right + rightTail).clamp(0.0, editable.size.width);
        if (right <= left) continue;
        final y = rect.bottom - paint.strokeWidth * 0.5;
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
      }
    }
  }

  void _paintBands(
    Canvas canvas,
    RenderEditable editable,
    List<Rect> bands,
    Color color, {
    required bool applyBackgroundTail,
  }) {
    if (color.a <= 0 || bands.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in _verticalPaintBands(
      editable,
      bands,
      applyBackgroundTail: applyBackgroundTail,
    )) {
      final leftTail = !applyBackgroundTail
          ? 0.0
          : _textDirection == TextDirection.rtl
              ? MarkupDecorationBoxMerger.styleBackgroundVisualEndTail
              : MarkupDecorationBoxMerger.styleBackgroundInnerTail;
      final rightTail = !applyBackgroundTail
          ? 0.0
          : _textDirection == TextDirection.rtl
              ? MarkupDecorationBoxMerger.styleBackgroundInnerTail
              : MarkupDecorationBoxMerger.styleBackgroundVisualEndTail;
      final band = Rect.fromLTRB(
        (rect.left - leftTail).clamp(0.0, editable.size.width).toDouble(),
        rect.top.clamp(0.0, editable.size.height).toDouble(),
        (rect.right + rightTail).clamp(0.0, editable.size.width).toDouble(),
        rect.bottom.clamp(0.0, editable.size.height).toDouble(),
      );
      if (band.width <= 0 || band.height <= 0) continue;
      final radius = Radius.circular((band.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(band, radius), paint);
    }
  }

  List<Rect> _verticalPaintBands(
    RenderEditable editable,
    List<Rect> bands, {
    required bool applyBackgroundTail,
  }) {
    final sorted = bands
        .where((band) => band.width > 0 && band.height > 0)
        .toList()
      ..sort((a, b) {
        final top = a.top.compareTo(b.top);
        return top != 0 ? top : a.left.compareTo(b.left);
      });
    if (sorted.isEmpty) return const [];

    final pad = applyBackgroundTail
        ? _styleBandVerticalPadding(editable)
        : _selectionBandVerticalPadding(editable);
    final painted = [
      for (final band in sorted)
        Rect.fromLTRB(band.left, band.top - pad, band.right, band.bottom + pad)
    ];
    final lineHeight = editable.preferredLineHeight;
    final bridgeGapLimit = lineHeight * 0.45;
    final maxAdjacentDistance = lineHeight * 1.55;
    final boundaryOverlap = applyBackgroundTail
        ? (lineHeight * 0.035).clamp(1.25, 3.0).toDouble()
        : 0.0;

    for (var i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];
      final centerDistance = next.center.dy - current.center.dy;
      if (centerDistance <= lineHeight * 0.25 ||
          centerDistance > maxAdjacentDistance) {
        continue;
      }

      final rowGap = next.top - current.bottom;
      if (rowGap > bridgeGapLimit) continue;

      final boundary = (current.bottom + next.top) / 2.0;
      if (boundary <= painted[i].top || boundary >= painted[i + 1].bottom) {
        continue;
      }
      painted[i] = Rect.fromLTRB(
        painted[i].left,
        painted[i].top,
        painted[i].right,
        boundary + boundaryOverlap,
      );
      painted[i + 1] = Rect.fromLTRB(
        painted[i + 1].left,
        boundary - boundaryOverlap,
        painted[i + 1].right,
        painted[i + 1].bottom,
      );
    }

    return painted;
  }

  double _styleBandVerticalPadding(RenderEditable editable) {
    return (editable.preferredLineHeight * 0.08).clamp(1.5, 8.0).toDouble();
  }

  double _selectionBandVerticalPadding(RenderEditable editable) {
    return (editable.preferredLineHeight * 0.045).clamp(1.0, 4.0).toDouble();
  }
}

class _BackgroundPaintRun {
  final TextRange range;
  final Color color;

  const _BackgroundPaintRun({
    required this.range,
    required this.color,
  });
}
