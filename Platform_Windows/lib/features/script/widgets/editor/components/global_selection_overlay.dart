import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../markup_controller.dart';
import '../../../../../core/extensions/string_extensions.dart';

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

  SelectionPointerState _pointerStateFor(Offset globalHandlePos) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null) return SelectionPointerState.stale;
    final local = stack.globalToLocal(globalHandlePos);
    final height = _stackSize.height;
    if (local.dy < -_hardExitMargin ||
        local.dy > height + _hardExitMargin ||
        local.dx < -_hardExitMargin ||
        local.dx > _stackSize.width + _hardExitMargin) {
      return SelectionPointerState.outside;
    }
    if (local.dy < _autoScrollZone || local.dy > height - _autoScrollZone) {
      return SelectionPointerState.edgeZone;
    }
    return SelectionPointerState.inside;
  }

  double _edgeScrollSpeed(Offset globalPointerPos) {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return 0;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null) return 0;
    if (_pointerStateFor(globalPointerPos) == SelectionPointerState.outside) {
      return 0;
    }
    final local = stack.globalToLocal(globalPointerPos);
    final height = _stackSize.height;
    double speed = 0;
    if (local.dy < _autoScrollZone) {
      // Near top — scroll up
      final factor =
          ((_autoScrollZone - local.dy) / _autoScrollZone).clamp(0.0, 1.0);
      speed = -_autoScrollMax * factor.toDouble();
    } else if (local.dy > height - _autoScrollZone) {
      // Near bottom — scroll down
      final factor = ((local.dy - (height - _autoScrollZone)) / _autoScrollZone)
          .clamp(0.0, 1.0);
      speed = _autoScrollMax * factor.toDouble();
    }
    if (speed < 0 && sc.offset <= sc.position.minScrollExtent) return 0;
    if (speed > 0 && sc.offset >= sc.position.maxScrollExtent) return 0;
    return speed;
  }

  void _updateHandleDragPointer(
    Offset pointerGlobal, {
    required bool updateEndpoint,
  }) {
    final session = _handleDrag;
    if (session == null) return;
    final handleGlobal = session.handleGlobalForPointer(pointerGlobal);
    session.latestPointerGlobal = pointerGlobal;
    session.latestHandleGlobal = handleGlobal;
    session.cancelStale();
    final state = _pointerStateFor(pointerGlobal);
    session.pointerState = state;
    _pointerState = state;

    if (state == SelectionPointerState.outside) {
      _suspendHandleDrag(
        pointerState: SelectionPointerState.outside,
        armStale: true,
      );
      return;
    }

    if (updateEndpoint && session.lastEndpointPointerGlobal != pointerGlobal) {
      session.lastEndpointPointerGlobal = pointerGlobal;
      _handleUpdate(handleGlobal, session.activeEndpointIsStart);
    }

    if (state == SelectionPointerState.edgeZone) {
      _ensureHandleAutoScroll();
    } else {
      _stopAutoScroll();
    }
  }

  void _ensureHandleAutoScroll() {
    final session = _handleDrag;
    if (session == null) return;
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return;
    final speed = _edgeScrollSpeed(session.latestPointerGlobal);
    if (speed == 0) {
      _stopAutoScroll();
      return;
    }
    session.autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        final activeSession = _handleDrag;
        if (!mounted) {
          _stopAutoScroll();
          return;
        }
        if (activeSession == null) return;
        if (!sc.hasClients) {
          _stopAutoScroll();
          return;
        }
        final state = _pointerStateFor(activeSession.latestPointerGlobal);
        activeSession.pointerState = state;
        _pointerState = state;
        if (state == SelectionPointerState.outside) {
          _suspendHandleDrag(
            pointerState: SelectionPointerState.outside,
            armStale: true,
          );
          return;
        }
        if (state == SelectionPointerState.inside) {
          _stopAutoScroll();
          return;
        }
        final tickSpeed = _edgeScrollSpeed(activeSession.latestPointerGlobal);
        if (tickSpeed == 0) {
          _stopAutoScroll();
          return;
        }
        final next = (sc.offset + tickSpeed)
            .clamp(sc.position.minScrollExtent, sc.position.maxScrollExtent)
            .toDouble();
        if (next == sc.offset) {
          _stopAutoScroll();
          return;
        }
        sc.jumpTo(next);
        _handleUpdate(
          activeSession.latestHandleGlobal,
          activeSession.activeEndpointIsStart,
        );
        refreshPositions();
      },
    );
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

  void _armStalePointerTimer() {
    final session = _handleDrag;
    if (session == null) return;
    session.cancelStale();
    session.staleTimer = Timer(_stalePointerTimeout, () {
      if (!mounted || _handleDrag != session) return;
      session.pointerState = SelectionPointerState.stale;
      _suspendHandleDrag(
        pointerState: SelectionPointerState.stale,
        armStale: false,
      );
    });
  }

  void _suspendHandleDrag({
    required SelectionPointerState pointerState,
    required bool armStale,
  }) {
    final session = _handleDrag;
    if (session == null) return;
    session.pointerState = pointerState;
    session.cancelAutoScroll();
    if (armStale) {
      _armStalePointerTimer();
    } else {
      session.cancelStale();
    }
    if (!mounted) return;
    setState(() {
      _ignoreBodyDragUntilPointerUp = true;
      _sessionMode = SelectionSessionMode.handleDrag;
      _pointerState = pointerState;
    });
  }

  void _stopAutoScroll() {
    _handleDrag?.cancelAutoScroll();
  }

  void _resetDragState() {
    _candidatePos = null;
    _candidateBlock = null;
    _candidateOffset = null;
    _bodyDragActive = false;
  }

  void _discardHandleDragSession() {
    _handleDrag?.cancelTimers();
    _handleDrag = null;
  }

  void _endHandleDrag({
    required String reason,
    required SelectionPointerState pointerState,
    required bool suppressBodyDragUntilPointerUp,
  }) {
    assert(reason.isNotEmpty);
    final session = _handleDrag;
    if (session == null) return;
    session.cancelTimers();
    _handleDrag = null;
    if (!mounted) return;
    setState(() {
      _ignoreBodyDragUntilPointerUp = suppressBodyDragUntilPointerUp;
      _sessionMode = hasSelection
          ? SelectionSessionMode.overlaySelection
          : SelectionSessionMode.none;
      _pointerState = pointerState;
    });
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
  /// Full-block selections are ignored here — Select All owns those.
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

  /// Body pointer-down: record the candidate AND eagerly cache the raw char
  /// offset at the pointer-down position. Do NOT activate global selection —
  /// that only happens when the pointer leaves the starting block.
  ///
  /// Caching the offset HERE (not at cross-block time) is what prevents the
  /// "anchor jump" the user reported: by the time the pointer crosses out of
  /// the starting block, the TextField may have abandoned its drag and the
  /// scroll view may have moved, so neither `controller.selection.baseOffset`
  /// nor a fresh `getPositionForPoint(_candidatePos)` is reliable anymore.
  void startDragging(Offset globalPos) {
    if (_handleDrag != null &&
        (_pointerState == SelectionPointerState.outside ||
            _pointerState == SelectionPointerState.stale)) {
      _endHandleDrag(
        reason: 'new-pointer',
        pointerState: SelectionPointerState.inside,
        suppressBodyDragUntilPointerUp: false,
      );
    }
    if (_ignoreBodyDragUntilPointerUp) return;
    _candidatePos = globalPos;
    _candidateBlock = _blockAtPosition(globalPos);
    _candidateOffset = null;
    _bodyDragActive = false;
    if (_candidateBlock != null) {
      final renderObj =
          widget.blockKeys[_candidateBlock!].currentContext?.findRenderObject();
      if (renderObj != null) {
        final editable = _findRenderEditable(renderObj);
        if (editable != null) {
          _candidateOffset = editable.getPositionForPoint(globalPos).offset;
        }
      }
    }
  }

  /// Body pointer-move: activate global selection iff the pointer has crossed
  /// into a different block than where the gesture started. Once active,
  /// extend the selection from the original origin to the current position.
  void updateDragging(Offset globalPos) {
    if (_ignoreBodyDragUntilPointerUp) return;
    if (_candidatePos == null) return;
    if (!_bodyDragActive) {
      final currentBlock = _blockAtPosition(globalPos);
      final crossed = currentBlock != null &&
          _candidateBlock != null &&
          currentBlock != _candidateBlock;
      final emptyToBlock = _candidateBlock == null && currentBlock != null;
      if (!crossed && !emptyToBlock) return;

      _bodyDragActive = true;
      _enterRefineMode();

      // Anchor priority for the start of the global selection:
      //  1. Cached char offset captured at pointer-down (most robust — frozen
      //     at the visual position the user actually clicked).
      //  2. The TextField's native selection.baseOffset (only valid if the
      //     TextField is still tracking the drag).
      //  3. Re-deriving the offset from the pointer-down GLOBAL position.
      if (_candidateBlock != null && _candidateOffset != null) {
        _anchorBlock = _candidateBlock;
        _anchorOffset = _candidateOffset;
      } else if (_candidateBlock != null) {
        final controller = widget.controllers[_candidateBlock!];
        if (controller.selection.isValid) {
          _anchorBlock = _candidateBlock;
          _anchorOffset = controller.selection.baseOffset;
        }
      }

      setState(() {
        _isSelecting = true;
        _sessionMode = SelectionSessionMode.overlaySelection;
        _pointerState = SelectionPointerState.inside;
        _focusEndpointIsStart = false;
        if (_anchorBlock != null) {
          _startBlock = _anchorBlock;
          _startOffset = _anchorOffset;
        } else {
          _handleUpdate(_candidatePos!, true);
        }
        _handleUpdate(globalPos, false);
      });
      return;
    }
    _handleUpdate(globalPos, false);
  }

  void endDragging() {
    if (_handleDrag != null) {
      _endHandleDrag(
        reason: 'pointer-up',
        pointerState: SelectionPointerState.inside,
        suppressBodyDragUntilPointerUp: false,
      );
    }
    _resetDragState();
    _ignoreBodyDragUntilPointerUp = false;
    _sessionMode = hasSelection
        ? SelectionSessionMode.overlaySelection
        : SelectionSessionMode.none;
    _pointerState = SelectionPointerState.inside;
    // Selection persists after drag
  }

  void _handleUpdate(Offset globalPos, bool isStart) {
    final RenderBox? overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final localPos = overlayBox.globalToLocal(globalPos);

    int? bestBlock;
    double minDistance = double.infinity;

    for (int i = 0; i < widget.blockKeys.length; i++) {
      final key = widget.blockKeys[i];
      final RenderBox? box =
          key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;

      final blockOffset = box.localToGlobal(Offset.zero);
      final localInOverlay = overlayBox.globalToLocal(blockOffset);
      final rect = localInOverlay & box.size;

      if (rect.contains(localPos)) {
        bestBlock = i;
        break;
      }

      // Fallback to nearest block if outside
      final dist = (rect.center - localPos).distance;
      if (dist < minDistance) {
        minDistance = dist;
        bestBlock = i;
      }
    }

    if (bestBlock != null) {
      final key = widget.blockKeys[bestBlock];
      final context = key.currentContext;
      if (context != null) {
        final RenderObject? renderObj = context.findRenderObject();
        if (renderObj != null) {
          final RenderEditable? editable = _findRenderEditable(renderObj);
          if (editable != null) {
            // getPositionForPoint expects a GLOBAL coordinate and converts
            // internally. The old code subtracted blockGlobalPos first which
            // caused a double-conversion and always returned line-1 positions.
            final pos = editable.getPositionForPoint(globalPos);

            setState(() {
              if (isStart) {
                _focusEndpointIsStart = true;
                _startBlock = bestBlock;
                _startOffset = pos.offset;
              } else {
                _focusEndpointIsStart = false;
                _endBlock = bestBlock;
                _endOffset = pos.offset;
              }
              _updateControllers();
            });
            // v4.1.13: Explicitly refresh handle positions after the frame
            // so they follow the drag in real-time.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) refreshPositions();
            });
            widget.onSelectionChanged();
          }
        }
      }
    }
  }

  void _updateControllers() {
    final range = _normalizedRange();
    if (range == null) return;

    for (int i = 0; i < widget.controllers.length; i++) {
      final c = widget.controllers[i];
      if (i < range.startBlock || i > range.endBlock) {
        c.isGlobalSelected = false;
        c.externalSelection = const TextSelection.collapsed(offset: 0);
      } else if (i > range.startBlock && i < range.endBlock) {
        c.isGlobalSelected = true;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
      } else if (i == range.startBlock && i == range.endBlock) {
        c.isGlobalSelected = false;
        final start = range.startOffset < range.endOffset
            ? range.startOffset
            : range.endOffset;
        final end = range.startOffset > range.endOffset
            ? range.startOffset
            : range.endOffset;
        c.externalSelection =
            TextSelection(baseOffset: start, extentOffset: end);
      } else if (i == range.startBlock) {
        c.isGlobalSelected = c.text.isEmpty;
        c.externalSelection = TextSelection(
            baseOffset: range.startOffset, extentOffset: c.text.length);
      } else if (i == range.endBlock) {
        c.isGlobalSelected = c.text.isEmpty;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: range.endOffset);
      }
      c.refresh();
    }
  }

  /// Recalculates handle positions after an external layout change (e.g. alignment
  /// applied to selected text). Must be called after the next frame so the
  /// RenderEditable has been laid out with the new textAlign/textDirection.
  void refreshPositions() {
    if (!hasSelection) {
      setState(() {
        _handleStartPos = null;
        _handleEndPos = null;
      });
      return;
    }

    final startPos = _getPositionInStack(_startBlock!, _startOffset!);
    final endPos = _getPositionInStack(_endBlock!, _endOffset!);

    setState(() {
      _handleStartPos = startPos;
      _handleEndPos = endPos;
    });
  }

  Offset? _getPositionInStack(int blockIdx, int offset) {
    if (blockIdx < 0 || blockIdx >= widget.blockKeys.length) return null;
    final key = widget.blockKeys[blockIdx];
    final renderObj = key.currentContext?.findRenderObject();
    if (renderObj == null) return null;

    final editable = _findRenderEditable(renderObj);
    final ourStack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (ourStack == null) return null;

    if (editable != null) {
      final caretOffset = editable.getLocalRectForCaret(
        TextPosition(offset: offset, affinity: TextAffinity.downstream),
      );
      final anchor = Offset(
        caretOffset.left,
        caretOffset.top + caretOffset.height / 2,
      );
      return editable.localToGlobal(anchor, ancestor: ourStack);
    }

    final box = renderObj as RenderBox;
    return box.localToGlobal(Offset.zero, ancestor: ourStack);
  }

  Offset _handleVisualCenter(Offset caret, bool endpointA) {
    final isRangeStart = _endpointIsRangeStart(endpointA);
    final block = endpointA ? _startBlock : _endBlock;
    final isRtl = block != null &&
        block >= 0 &&
        block < widget.controllers.length &&
        widget.controllers[block].text.isHebrew;
    final placeLeftOfCaret = isRtl ? !isRangeStart : isRangeStart;
    final dx = placeLeftOfCaret
        ? caret.dx - _handleBarWidth / 2 - 2.0
        : caret.dx + _handleBarWidth / 2 + 2.0;
    return Offset(dx, caret.dy);
  }

  /// v4.0.8: Called after a style command mutates text so that _startOffset /
  /// _endOffset stay in sync with the new externalSelection positions set by
  /// wrapSelection.  Each affected controller already has its externalSelection
  /// updated to the post-insert range before this method is called.
  void syncOffsetsFromExternalSelection(List<MarkupController> controllers) {
    if (_startBlock == null || _endBlock == null) return;
    if (_startBlock! < controllers.length) {
      final c = controllers[_startBlock!];
      if (c.externalSelection != null &&
          c.externalSelection!.isValid &&
          !c.externalSelection!.isCollapsed) {
        _startOffset = c.externalSelection!.start;
      }
    }
    if (_endBlock! < controllers.length) {
      final c = controllers[_endBlock!];
      if (c.externalSelection != null &&
          c.externalSelection!.isValid &&
          !c.externalSelection!.isCollapsed) {
        _endOffset = c.externalSelection!.end;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refreshPositions();
    });
  }

  void _updateBlockHighlights() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) return;

    // Ensure start is before end
    int sB = _startBlock!, eB = _endBlock!;
    int sO = _startOffset!, eO = _endOffset!;
    if (sB > eB || (sB == eB && sO > eO)) {
      final tB = sB;
      sB = eB;
      eB = tB;
      final tO = sO;
      sO = eO;
      eO = tO;
    }

    for (int i = 0; i < widget.controllers.length; i++) {
      final c = widget.controllers[i];
      if (i < sB || i > eB) {
        // Use a collapsed (non-null) selection to explicitly suppress any
        // highlight. Setting null would fall through to the native
        // controller.selection, which may still hold a range from a prior
        // user gesture and would show a stale amber highlight.
        c.externalSelection = const TextSelection.collapsed(offset: 0);
      } else if (i == sB && i == eB) {
        c.externalSelection = TextSelection(baseOffset: sO, extentOffset: eO);
      } else if (i == sB) {
        c.externalSelection =
            TextSelection(baseOffset: sO, extentOffset: c.text.length);
      } else if (i == eB) {
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: eO);
      } else {
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }
  }

  bool? _nearestHandleForPointer(Offset globalPos, {required bool fallback}) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return fallback;

    double? distanceTo(Offset? caret, bool endpointA) {
      if (caret == null) return null;
      final center = _handleVisualCenter(caret, endpointA);
      final globalCenter = stackBox.localToGlobal(center);
      final delta = globalCenter - globalPos;
      return delta.dx * delta.dx + delta.dy * delta.dy;
    }

    final startDistance = distanceTo(_handleStartPos, true);
    final endDistance = distanceTo(_handleEndPos, false);
    if (startDistance == null && endDistance == null) return fallback;
    if (startDistance == null) return false;
    if (endDistance == null) return true;
    return startDistance <= endDistance;
  }

  void _enterRefineMode() {
    if (!_isWholeScriptSelected) return;
    for (final c in widget.controllers) {
      c.isGlobalSelected = false;
      c.refresh(); // repaint TextFields immediately so isGlobalSelected=false takes effect
    }
    widget.onSelectionChanged();
    // Note: native controller.selection is intentionally NOT collapsed here.
    // selectionColor is always transparent (set in _EditorBlock), so RenderEditable
    // never paints its own amber regardless of native selection state.
    // Collapsing native selection was causing _getPositionForPoint() to misreport
    // positions on the second visual line of wrapped text blocks (multi-line drag bug).
  }

  @override
  void dispose() {
    _discardHandleDragSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        // Only show a handle when its block is currently rendered (position
        // known). If the block has scrolled offscreen, _handleStartPos /
        // _handleEndPos is null. We hide the handle instead of clamping it
        // to a viewport edge — a handle floating at an unrelated edge is
        // confusing and doesn't correspond to any real text position.
        final start = hasSelection ? _handleStartPos : null;
        final end = hasSelection ? _handleEndPos : null;
        return Stack(
          key: _stackKey,
          children: [
            // Recalculate handle positions whenever the scroll view moves so
            // handles follow the text even when the user scrolls while a
            // selection is active. Using NotificationListener instead of a
            // scroll-controller addListener keeps the overlay self-contained.
            NotificationListener<ScrollNotification>(
              onNotification: (_) {
                if (_isSelecting) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) refreshPositions();
                  });
                }
                return false; // let notification bubble
              },
              child: widget.child,
            ),
            if (_handleDrag?.activeEndpointIsStart == false) ...[
              if (start != null) _buildHandle(start, true),
              if (end != null) _buildHandle(end, false),
            ] else ...[
              if (end != null) _buildHandle(end, false),
              if (start != null) _buildHandle(start, true),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHandle(Offset pos, bool isStart) {
    final visualCenter = _handleVisualCenter(pos, isStart);
    // Hide handles whose caret is outside the visible stack area.
    // Without this check the handle would clamp to a viewport edge even though
    // the selected text is scrolled fully offscreen.
    if (visualCenter.dy < -56 ||
        visualCenter.dy > _stackSize.height + 56 ||
        visualCenter.dx < -40 ||
        visualCenter.dx > _stackSize.width + 40) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: (visualCenter.dx - _handleHitWidth / 2).clamp(
        0.0,
        _stackSize.width > _handleHitWidth
            ? _stackSize.width - _handleHitWidth
            : 0.0,
      ),
      top: (visualCenter.dy - _handleHitHeight / 2).clamp(
        0.0,
        _stackSize.height > _handleHitHeight
            ? _stackSize.height - _handleHitHeight
            : 0.0,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _enterRefineMode();
          final activeSide = _nearestHandleForPointer(details.globalPosition,
                  fallback: isStart) ??
              isStart;
          // v4.0.9: Convert the handle's Stack-local caret position to GLOBAL
          // coordinates HERE (layout is guaranteed valid from the previous frame).
          // Subsequent onPanUpdate calls just add the finger delta to this global
          // caret origin, so the caret — not the touch-point — drives
          // _handleUpdate.  This eliminates the line-1 snap that occurred when
          // the user's finger landed at the top of the 56-px hit area (18 px
          // above the caret) and the raw touch y was mapped to line 1 instead.
          final stackBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final logicalStackLocal =
              activeSide ? _handleStartPos : _handleEndPos;
          final caretGlobal = (stackBox != null && logicalStackLocal != null)
              ? stackBox.localToGlobal(logicalStackLocal)
              : null;
          _handleDrag?.cancelTimers();
          final session = _HandleDragSession(
            activeEndpointIsStart: activeSide,
            panStartPointerGlobal: details.globalPosition,
            panStartHandleGlobal: caretGlobal,
            latestPointerGlobal: details.globalPosition,
            latestHandleGlobal: caretGlobal ?? details.globalPosition,
          );
          setState(() {
            _handleDrag = session;
            _sessionMode = SelectionSessionMode.handleDrag;
            _pointerState = SelectionPointerState.inside;
            _focusEndpointIsStart = activeSide;
            _ignoreBodyDragUntilPointerUp = false;
            _candidatePos = null;
            _candidateBlock = null;
            _candidateOffset = null;
            _bodyDragActive = false;
          });
        },
        onPanUpdate: (details) {
          _updateHandleDragPointer(
            details.globalPosition,
            updateEndpoint: true,
          );
        },
        onPanEnd: (_) => endHandleGesturePreserveSelection(reason: 'pan-end'),
        onPanCancel: () =>
            endHandleGesturePreserveSelection(reason: 'pan-cancel'),
        child: Container(
          width: _handleHitWidth,
          height: _handleHitHeight,
          color: Colors.transparent, // Hit test area
          child: Center(
            child: Container(
              width: _handleBarWidth,
              height: _handleBarHeight,
              decoration: BoxDecoration(
                color: const Color(0xFFFFBF00),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
