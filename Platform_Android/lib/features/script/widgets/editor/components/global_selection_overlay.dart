import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../markup_controller.dart';
import '../../../services/editor_text_geometry_service.dart';
import '../../../services/markup_decoration_service.dart';

part 'global_selection_overlay.body_drag.dart';
part 'global_selection_overlay.rendering.dart';
part 'global_selection_overlay.handles.dart';

/// Walk a render tree to find the first RenderEditable.
RenderEditable? _findRenderEditable(RenderObject obj) {
  if (obj is RenderEditable) return obj;
  RenderEditable? result;
  obj.visitChildren((child) {
    result ??= _findRenderEditable(child);
  });
  return result;
}

enum SelectionSessionMode {
  none,
  overlaySelection,
  handleDrag,
  keyboardExtend,
}

enum SelectionPointerState {
  inside,
  edgeZone,
  outside,
  stale,
}

class SelectionEndpoint {
  final int block;
  final int offset;

  const SelectionEndpoint({required this.block, required this.offset});

  @override
  String toString() => '$block:$offset';
}

class SelectionSessionSnapshot {
  final SelectionSessionMode mode;
  final SelectionPointerState pointerState;
  final SelectionEndpoint endpointA;
  final SelectionEndpoint endpointB;
  final SelectionEndpoint anchor;
  final SelectionEndpoint focus;
  final bool focusEndpointIsA;

  const SelectionSessionSnapshot({
    required this.mode,
    required this.pointerState,
    required this.endpointA,
    required this.endpointB,
    required this.anchor,
    required this.focus,
    required this.focusEndpointIsA,
  });
}

class _HandleDragSession {
  final bool activeEndpointIsStart;
  final Offset panStartPointerGlobal;
  final Offset? panStartHandleGlobal;
  Offset latestPointerGlobal;
  Offset latestHandleGlobal;
  Offset? lastEndpointPointerGlobal;
  SelectionPointerState pointerState = SelectionPointerState.inside;
  Timer? autoScrollTimer;
  Timer? staleTimer;

  _HandleDragSession({
    required this.activeEndpointIsStart,
    required this.panStartPointerGlobal,
    required this.panStartHandleGlobal,
    required this.latestPointerGlobal,
    required this.latestHandleGlobal,
  });

  Offset handleGlobalForPointer(Offset pointerGlobal) {
    final handleStart = panStartHandleGlobal;
    if (handleStart == null) return pointerGlobal;
    return handleStart + (pointerGlobal - panStartPointerGlobal);
  }

  void cancelAutoScroll() {
    autoScrollTimer?.cancel();
    autoScrollTimer = null;
  }

  void cancelStale() {
    staleTimer?.cancel();
    staleTimer = null;
  }

  void cancelTimers() {
    cancelAutoScroll();
    cancelStale();
  }
}

/// v3.9.5.66: Global Multi-Paragraph Selection Manager
/// Coordinates drag-handles and selection highlights across independent TextField blocks.
class GlobalSelectionOverlay extends StatefulWidget {
  final List<MarkupController> controllers;
  final List<GlobalKey> blockKeys;
  final Widget child;
  final VoidCallback onSelectionChanged;

  /// Editor scroll controller. When provided, dragging a selection handle
  /// near the top or bottom of the viewport automatically scrolls the list,
  /// letting users extend selections beyond the visible area.
  final ScrollController? scrollController;

  const GlobalSelectionOverlay({
    super.key,
    required this.controllers,
    required this.blockKeys,
    required this.child,
    required this.onSelectionChanged,
    this.scrollController,
  });

  @override
  State<GlobalSelectionOverlay> createState() => GlobalSelectionOverlayState();
}

class GlobalSelectionOverlayState extends State<GlobalSelectionOverlay> {
  // Global selection state
  int? _startBlock, _endBlock;
  int? _startOffset, _endOffset;

  // Interaction state
  bool _isSelecting = false;
  Offset? _handleStartPos, _handleEndPos;
  Size _stackSize = Size.zero;
  _HandleDragSession? _handleDrag;
  bool _ignoreBodyDragUntilPointerUp = false;
  bool _focusEndpointIsStart = false;
  SelectionSessionMode _sessionMode = SelectionSessionMode.none;
  SelectionPointerState _pointerState = SelectionPointerState.inside;

  // Anchor state for body-drag to prevent jumping
  int? _anchorBlock;
  int? _anchorOffset;

  final GlobalKey _stackKey = GlobalKey();

  // Drag-handle autoscroll: when a handle is dragged within [_autoScrollZone]
  // pixels of the top/bottom edge, a periodic timer scrolls the list so the
  // user can extend the selection beyond the visible viewport.
  static const double _autoScrollZone = 60.0; // px from edge to trigger
  static const double _autoScrollMax = 40.0; // max px per tick (at edge)
  static const double _handleHitWidth = 40.0;
  static const double _handleHitHeight = 56.0;
  static const double _handleBarWidth = 6.0;
  static const double _handleBarHeight = 40.0;
  static const double _hardExitMargin = 80.0;
  static const Duration _stalePointerTimeout = Duration(milliseconds: 2500);

  bool get isHandleInteractionActive => _handleDrag != null;

  SelectionSessionSnapshot? get selectionSessionSnapshot {
    if (!hasSelection ||
        _startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return null;
    }
    final endpointA = SelectionEndpoint(
      block: _startBlock!,
      offset: _clampEndpointOffset(_startBlock!, _startOffset!),
    );
    final endpointB = SelectionEndpoint(
      block: _endBlock!,
      offset: _clampEndpointOffset(_endBlock!, _endOffset!),
    );
    return SelectionSessionSnapshot(
      mode: _sessionMode,
      pointerState: _pointerState,
      endpointA: endpointA,
      endpointB: endpointB,
      anchor: _focusEndpointIsStart ? endpointB : endpointA,
      focus: _focusEndpointIsStart ? endpointA : endpointB,
      focusEndpointIsA: _focusEndpointIsStart,
    );
  }

  bool isPointInsideHandle(Offset globalPos) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !hasSelection) return false;

    bool contains(Offset? caret, bool endpointA) {
      if (caret == null) return false;
      final center = _handleVisualCenter(caret, endpointA);
      final rect = Rect.fromCenter(
        center: center,
        width: _handleHitWidth,
        height: _handleHitHeight,
      );
      return rect.contains(stackBox.globalToLocal(globalPos));
    }

    return contains(_handleStartPos, true) || contains(_handleEndPos, false);
  }

  void updateActiveHandlePointer(Offset pointerGlobal) {
    _updateHandleDragPointer(pointerGlobal, updateEndpoint: true);
  }

  void handlePointerExitedEditor(Offset pointerGlobal) {
    final session = _handleDrag;
    if (session == null) return;
    final handleGlobal = session.handleGlobalForPointer(pointerGlobal);
    final state = _pointerStateFor(pointerGlobal);
    session.latestPointerGlobal = pointerGlobal;
    session.latestHandleGlobal = handleGlobal;
    session.pointerState = state;
    _pointerState = state;
    if (state == SelectionPointerState.outside) {
      _suspendHandleDrag(
        pointerState: SelectionPointerState.outside,
        armStale: true,
      );
      return;
    }
    if (state == SelectionPointerState.edgeZone) {
      _ensureHandleAutoScroll();
    } else {
      _stopAutoScroll();
    }
    _armStalePointerTimer();
  }

  void endHandleGesturePreserveSelection({String reason = 'end'}) {
    final state = reason == 'stale-pointer'
        ? SelectionPointerState.stale
        : reason.startsWith('outside') || reason == 'editor-exit'
            ? SelectionPointerState.outside
            : SelectionPointerState.inside;
    _endHandleDrag(
      reason: reason,
      pointerState: state,
      suppressBodyDragUntilPointerUp:
          reason != 'pan-end' && reason != 'pan-cancel' && reason != 'end',
    );
  }

  // Body-pointer candidate state: pointer-down does NOT immediately start a
  // global selection. We record the origin and the block it landed in, then
  // only activate global selection if the pointer drags into a DIFFERENT
  // block. This lets click + in-block drag stay native (TextField handles it),
  // and only cross-block drags become multi-paragraph selections.
  // We CACHE the raw character offset at pointer-down (anchor-lock). On
  // cross-block activation we use that cached offset as the start anchor so
  // the selection's origin doesn't drift if the view scrolled or layout
  // shifted between pointer-down and the block-cross moment.
  Offset? _candidatePos;
  int? _candidateBlock;
  int? _candidateOffset; // cached raw char offset at pointer-down
  bool _bodyDragActive = false;
  Offset? _latestBodyDragGlobal;
  Timer? _bodyAutoScrollTimer;

  // A plain drag across the editor should scroll, not select. Cross-block
  // selection only activates once this is armed by a long-press hold at the
  // touch-down point (see _armSelectionAfterLongPress in
  // script_editor_screen.build.dart), or when the starting block already has
  // a native partial selection (from a double-tap word-select being dragged).
  bool _selectionGestureArmed = false;

  /// True when every block is wholly selected (post Select All, pre refine).
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

  ({
    int startBlock,
    int startOffset,
    int endBlock,
    int endOffset,
  })? get currentRawRange {
    if (!hasSelection ||
        _startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return null;
    }
    return (
      startBlock: _startBlock!,
      startOffset: _clampEndpointOffset(_startBlock!, _startOffset!),
      endBlock: _endBlock!,
      endOffset: _clampEndpointOffset(_endBlock!, _endOffset!),
    );
  }

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
  void extendNativeBlockSelection(
    int blockIndex,
    TextSelection selection, {
    bool allowFullBlock = false,
  }) {
    if (blockIndex < 0 || blockIndex >= widget.controllers.length) return;
    if (!selection.isValid || selection.isCollapsed) return;
    final controller = widget.controllers[blockIndex];
    final start = selection.start.clamp(0, controller.text.length).toInt();
    final end = selection.end.clamp(0, controller.text.length).toInt();
    if (start == end) return;
    if (!allowFullBlock && start == 0 && end == controller.text.length) {
      return;
    }
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

  /// Called after the body Listener detects a long-press hold with minimal
  /// movement, arming the NEXT drag update to start/extend a cross-block
  /// selection instead of being ignored in favor of scrolling.
  void armSelectionGesture() {
    _selectionGestureArmed = true;
  }

  void startDragging(Offset globalPos) =>
      _GlobalSelectionOverlayBodyDragParts(this).startDragging(globalPos);

  void updateDragging(Offset globalPos) =>
      _GlobalSelectionOverlayBodyDragParts(this).updateDragging(globalPos);

  void endDragging() =>
      _GlobalSelectionOverlayBodyDragParts(this).endDragging();

  void handleBodyPointerExitedEditor(Offset globalPos) =>
      _GlobalSelectionOverlayBodyDragParts(this)
          .handleBodyPointerExitedEditor(globalPos);

  void _updateControllers() =>
      _GlobalSelectionOverlayRenderingParts(this)._updateControllers();

  void refreshPositions() =>
      _GlobalSelectionOverlayRenderingParts(this).refreshPositions();

  Offset _handleVisualCenter(Offset caret, bool endpointA) =>
      _GlobalSelectionOverlayRenderingParts(this)
          ._handleVisualCenter(caret, endpointA);

  void syncOffsetsFromExternalSelection(List<MarkupController> controllers) =>
      _GlobalSelectionOverlayRenderingParts(this)
          .syncOffsetsFromExternalSelection(controllers);

  void _updateBlockHighlights() =>
      _GlobalSelectionOverlayRenderingParts(this)._updateBlockHighlights();

  void _enterRefineMode() =>
      _GlobalSelectionOverlayRenderingParts(this)._enterRefineMode();

  @override
  void dispose() {
    _discardHandleDragSession();
    _stopBodyAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _GlobalSelectionOverlayRenderingParts(this).build(context);
}
