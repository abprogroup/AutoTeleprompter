part of 'script_editor_screen.dart';

class _EditorRenderEditableDecorations extends SingleChildRenderObjectWidget {
  final TextEditingController controller;
  final TextSelection? selection;
  final TextDirection textDirection;

  const _EditorRenderEditableDecorations({
    required this.controller,
    required this.selection,
    required this.textDirection,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEditorRenderEditableDecorations(
      controller: controller,
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
      ..selection = selection
      ..textDirection = textDirection;
  }
}

class _RenderEditorRenderEditableDecorations extends RenderProxyBox {
  TextEditingController _controller;
  TextSelection? _selection;
  TextDirection _textDirection;
  bool _listeningToController = false;

  _RenderEditorRenderEditableDecorations({
    required TextEditingController controller,
    required TextSelection? selection,
    required TextDirection textDirection,
  })  : _controller = controller,
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
  }

  @override
  void detach() {
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

  void _handleControllerChanged() => markNeedsPaint();

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
    for (final range in MarkupDecorationParser.decorationRanges(_rawText)) {
      if (range.type != MarkupDecorationType.background) continue;
      final paintable =
          MarkupDecorationParser.paintableContentRange(_rawText, range);
      if (paintable == null) continue;
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(baseOffset: paintable.start, extentOffset: paintable.end),
        gapTolerance: MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
      );
      _paintBands(canvas, editable, bands, range.color ?? Colors.transparent,
          applyBackgroundTail: true);
    }
  }

  void _paintActiveSelection(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomEditorSelectionPainting) return;
    final activeSelection = _selection;
    if (activeSelection == null ||
        !activeSelection.isValid ||
        activeSelection.isCollapsed) {
      return;
    }
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      activeSelection,
      gapTolerance: MarkupDecorationBoxMerger.activeSelectionGapTolerance,
    );
    _paintBands(canvas, editable, bands, const Color(0x66FFBF00),
        applyBackgroundTail: false);
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
      final paintable =
          MarkupDecorationParser.paintableContentRange(_rawText, range);
      if (paintable == null) continue;
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(baseOffset: paintable.start, extentOffset: paintable.end),
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
    if (color == color.withAlpha(0) || bands.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in bands) {
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
        rect.top,
        (rect.right + rightTail).clamp(0.0, editable.size.width).toDouble(),
        rect.bottom,
      );
      if (band.width <= 0 || band.height <= 0) continue;
      final radius = Radius.circular((band.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(band, radius), paint);
    }
  }
}
