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
    _setOverlayState(() {
      _isSelecting = false;
      _startBlock = _endBlock = null;
      _startOffset = _endOffset = null;
      _handleStartPos = null;
      _handleEndPos = null;
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
    _setOverlayState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.overlaySelection;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = 0;
      _startOffset = 0;
      _endBlock = widget.controllers.length - 1;
      _endOffset = widget.controllers.last.text.length;
      _handleStartPos = null;
      _handleEndPos = null;
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
    _setOverlayState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.keyboardExtend;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = anchorBlock;
      _startOffset = _clampEndpointOffset(anchorBlock, anchorOffset);
      _endBlock = focusBlock;
      _endOffset = _clampEndpointOffset(focusBlock, focusOffset);
      _handleStartPos = null;
      _handleEndPos = null;
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
    final handles =
        'handles:${_formatDebugOffset(_handleStartPos)}-${_formatDebugOffset(_handleEndPos)}';
    return '$a $b $active $focus mode:${_sessionMode.name} '
        'pointer:${_pointerState.name} $normalized $handles '
        'lastEvent=$_lastSelectionDebugEvent';
  }

  String _formatDebugOffset(Offset? offset) {
    if (offset == null) return '-';
    return '${offset.dx.toStringAsFixed(1)},${offset.dy.toStringAsFixed(1)}';
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
  /// Full-block selections are ignored here - Select All owns those.
  void extendNativeBlockSelection(
    int blockIndex,
    TextSelection selection, {
    bool allowFullBlock = false,
  }) {
    if (blockIndex < 0 || blockIndex >= widget.controllers.length) return;
    if (!selection.isValid || selection.isCollapsed) return;
    final controller = widget.controllers[blockIndex];
    final base = selection.baseOffset.clamp(0, controller.text.length).toInt();
    final extent =
        selection.extentOffset.clamp(0, controller.text.length).toInt();
    final start = base < extent ? base : extent;
    final end = base > extent ? base : extent;
    if (start == end) return;
    if (!allowFullBlock && start == 0 && end == controller.text.length) {
      return;
    }
    _setOverlayState(() {
      _isSelecting = true;
      _sessionMode = SelectionSessionMode.overlaySelection;
      _pointerState = SelectionPointerState.inside;
      _focusEndpointIsStart = false;
      _startBlock = blockIndex;
      _endBlock = blockIndex;
      _startOffset = base;
      _endOffset = extent;
      _handleStartPos = null;
      _handleEndPos = null;
      for (final c in widget.controllers) {
        c.isGlobalSelected = false;
      }
      _updateControllers();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
    widget.onSelectionChanged();
  }
}
