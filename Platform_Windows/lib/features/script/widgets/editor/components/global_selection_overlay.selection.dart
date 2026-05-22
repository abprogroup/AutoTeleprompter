part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlaySelection on GlobalSelectionOverlayState {
  bool get _isWholeScriptSelected =>
      widget.controllers.isNotEmpty &&
      widget.controllers.every((c) => c.isGlobalSelected);

  void clearSelection() {
    _discardHandleDragSession();
    _resetDragState();
    _ignoreBodyDragUntilPointerUp = false;
    _sessionMode = SelectionSessionMode.none;
    _pointerState = SelectionPointerState.inside;
    if (!_isSelecting) return;
    setState(() {
      _isSelecting = false;
      _startBlock = _endBlock = null;
      _startOffset = _endOffset = null;
      _anchorBlock = _anchorOffset = null;
      for (final c in widget.controllers) {
        c.externalSelection = null;
        c.externalVisibleSelection = null;
        c.isGlobalSelected = false;
        c.refresh();
      }
    });
    widget.onSelectionChanged();
  }

  void selectAll() {
    if (widget.controllers.isEmpty) return;
    _discardHandleDragSession();
    setState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.overlaySelection;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = 0;
      _startOffset = 0;
      _endBlock = widget.controllers.length - 1;
      _endOffset = widget.controllers.last.text.length;
      for (final c in widget.controllers) {
        c.isGlobalSelected = true;
        c.externalVisibleSelection = TextSelection(
          baseOffset: 0,
          extentOffset: MarkupDecorationParser.visibleText(c.text).length,
        );
      }
      _updateBlockHighlights();
      // v3.9.5.73: Trust parent setState for initial draw,
      // only refresh controllers to ensure individual TextFields repaint.
      for (final c in widget.controllers) {
        c.refresh();
      }
    });
    // Recalculate handle positions after the frame so RenderEditables are
    // laid out with their selection highlights before we read caret coords.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
    widget.onSelectionChanged();
  }

  bool get hasSelection =>
      _isSelecting && _startBlock != null && _endBlock != null;

  void setKeyboardSelection({
    required int anchorBlock,
    required int anchorOffset,
    required int focusBlock,
    required int focusOffset,
  }) {
    if (anchorBlock < 0 ||
        anchorBlock >= widget.controllers.length ||
        focusBlock < 0 ||
        focusBlock >= widget.controllers.length) {
      return;
    }
    _discardHandleDragSession();
    _resetDragState();
    setState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.keyboardExtend;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = anchorBlock;
      _startOffset = _clampEndpointOffset(anchorBlock, anchorOffset);
      _endBlock = focusBlock;
      _endOffset = _clampEndpointOffset(focusBlock, focusOffset);
      for (final c in widget.controllers) {
        c.isGlobalSelected = false;
        c.externalVisibleSelection = null;
      }
      _updateControllers();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
    widget.onSelectionChanged();
  }

  String get debugSelectionSummary {
    final range = _normalizedRange();
    final session = selectionSessionSnapshot;
    final a =
        _startBlock == null ? 'A:-' : 'A:$_startBlock:${_startOffset ?? '-'}';
    final b = _endBlock == null ? 'B:-' : 'B:$_endBlock:${_endOffset ?? '-'}';
    final active = _handleDrag == null
        ? 'active:none'
        : 'active:${_handleDrag!.activeEndpointIsStart ? 'A' : 'B'}';
    final normalized = range == null
        ? 'range:-'
        : 'range:${range.startBlock}:${range.startOffset}-${range.endBlock}:${range.endOffset}';
    final focus = session == null
        ? 'focus:-'
        : 'anchor:${session.anchor} focus:${session.focus}';
    return '$a $b $active $focus mode:${_sessionMode.name} pointer:${_pointerState.name} $normalized';
  }

  int _clampEndpointOffset(int block, int offset) {
    if (block < 0 || block >= widget.controllers.length) return 0;
    return offset.clamp(0, widget.controllers[block].text.length).toInt();
  }

  int _compareEndpoints({
    required int aBlock,
    required int aOffset,
    required int bBlock,
    required int bOffset,
  }) {
    if (aBlock != bBlock) return aBlock.compareTo(bBlock);
    return aOffset.compareTo(bOffset);
  }

  ({
    int startBlock,
    int startOffset,
    int endBlock,
    int endOffset,
    bool endpointAIsStart,
  })? _normalizedRange() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return null;
    }
    final aBlock = _startBlock!;
    final bBlock = _endBlock!;
    final aOffset = _clampEndpointOffset(aBlock, _startOffset!);
    final bOffset = _clampEndpointOffset(bBlock, _endOffset!);
    final endpointAFirst = _compareEndpoints(
          aBlock: aBlock,
          aOffset: aOffset,
          bBlock: bBlock,
          bOffset: bOffset,
        ) <=
        0;
    return endpointAFirst
        ? (
            startBlock: aBlock,
            startOffset: aOffset,
            endBlock: bBlock,
            endOffset: bOffset,
            endpointAIsStart: true,
          )
        : (
            startBlock: bBlock,
            startOffset: bOffset,
            endBlock: aBlock,
            endOffset: aOffset,
            endpointAIsStart: false,
          );
  }

  bool _endpointIsRangeStart(bool endpointA) {
    final range = _normalizedRange();
    if (range == null) return endpointA;
    return endpointA ? range.endpointAIsStart : !range.endpointAIsStart;
  }

  /// Converts a native single-block partial selection (e.g. from double-click
  /// or drag-to-select inside one TextField) into the app overlay handles.
  /// Full-block selections are ignored here â€” Select All owns those.
  void extendNativeBlockSelection(int blockIndex, TextSelection selection) {
    if (blockIndex < 0 || blockIndex >= widget.controllers.length) return;
    if (!selection.isValid || selection.isCollapsed) return;
    final controller = widget.controllers[blockIndex];
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (start == 0 && end == controller.text.length) return;
    setState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.overlaySelection;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = blockIndex;
      _endBlock = blockIndex;
      _startOffset = start;
      _endOffset = end;
      for (final c in widget.controllers) c.isGlobalSelected = false;
      _updateControllers();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
    widget.onSelectionChanged();
  }

  /// Returns the block index whose render box contains [globalPos], or null.
  int? _blockAtPosition(Offset globalPos) {
    for (int i = 0; i < widget.blockKeys.length; i++) {
      final box =
          widget.blockKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final local = box.globalToLocal(globalPos);
      if (local.dx >= 0 &&
          local.dx <= box.size.width &&
          local.dy >= 0 &&
          local.dy <= box.size.height) {
        return i;
      }
    }
    return null;
  }
}
