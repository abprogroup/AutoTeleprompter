import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../markup_controller.dart';
import '../../../services/editor_text_geometry_service.dart';
import '../../../services/markup_decoration_service.dart';

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

/// v3.9.5.66: Global Multi-Paragraph Selection Manager
/// Coordinates drag-handles and selection highlights across independent TextField blocks.
class GlobalSelectionOverlay extends StatefulWidget {
  final List<MarkupController> controllers;
  final List<GlobalKey> blockKeys;
  final Widget child;
  final VoidCallback onSelectionChanged;

  const GlobalSelectionOverlay({
    super.key,
    required this.controllers,
    required this.blockKeys,
    required this.child,
    required this.onSelectionChanged,
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
  bool _draggingStart = false;
  bool _draggingEnd = false;
  bool _keyboardFocusEndpointIsStart = false;
  bool _hasHandleRefinedSelection = false;
  Size _stackSize = Size.zero;

  // Delta-drag state: track finger start (global) and the handle's caret start
  // position (also global, converted at pan-start while layout is valid).
  Offset? _panStartGlobal;
  Offset?
      _panStartHandleGlobal; // caret global position at the moment of pan start
  final GlobalKey _stackKey = GlobalKey();

  /// True when every block is wholly selected (post Select All, pre refine).
  bool get _isWholeScriptSelected =>
      widget.controllers.isNotEmpty &&
      widget.controllers.every((c) => c.isGlobalSelected);

  void clearSelection() {
    if (!_isSelecting) return;
    setState(() {
      _isSelecting = false;
      _keyboardFocusEndpointIsStart = false;
      _draggingStart = false;
      _draggingEnd = false;
      _hasHandleRefinedSelection = false;
      _startBlock = _endBlock = null;
      _startOffset = _endOffset = null;
      for (final c in widget.controllers) {
        c.externalSelection = null;
        c.isGlobalSelected = false;
        c.refresh();
      }
    });
    widget.onSelectionChanged();
  }

  void endDragging() {
    if (!_draggingStart && !_draggingEnd) return;
    setState(() {
      _draggingStart = false;
      _draggingEnd = false;
    });
  }

  void selectAll() {
    if (widget.controllers.isEmpty) return;
    setState(() {
      _isSelecting = true;
      _hasHandleRefinedSelection = false;
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
      setState(() => _calculateHandlePositions());
    });
    widget.onSelectionChanged();
  }

  bool get hasSelection =>
      _isSelecting && _startBlock != null && _endBlock != null;

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
      mode: _draggingStart || _draggingEnd
          ? SelectionSessionMode.handleDrag
          : SelectionSessionMode.overlaySelection,
      pointerState: SelectionPointerState.inside,
      endpointA: endpointA,
      endpointB: endpointB,
      anchor: _keyboardFocusEndpointIsStart ? endpointB : endpointA,
      focus: _keyboardFocusEndpointIsStart ? endpointA : endpointB,
      focusEndpointIsA: _keyboardFocusEndpointIsStart,
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
    setState(() {
      _isSelecting = true;
      _hasHandleRefinedSelection = true;
      _draggingStart = false;
      _draggingEnd = false;
      _startBlock = anchorBlock;
      _startOffset = _clampEndpointOffset(anchorBlock, anchorOffset);
      _endBlock = focusBlock;
      _endOffset = _clampEndpointOffset(focusBlock, focusOffset);
      _keyboardFocusEndpointIsStart = false;
      for (final c in widget.controllers) {
        c.isGlobalSelected = false;
      }
      _updateBlockHighlights();
      for (final c in widget.controllers) {
        c.refresh();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _calculateHandlePositions());
    });
    widget.onSelectionChanged();
  }

  int _clampEndpointOffset(int block, int offset) {
    if (block < 0 || block >= widget.controllers.length) return 0;
    return offset.clamp(0, widget.controllers[block].text.length).toInt();
  }

  bool get isRefinedSelection => _hasHandleRefinedSelection;

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
      startOffset: _startOffset!,
      endBlock: _endBlock!,
      endOffset: _endOffset!,
    );
  }

  /// Explicitly converts a user-confirmed native partial selection into the app
  /// overlay handles. This must only be called from an intentional UI command
  /// path (the editor native/adaptive context-menu build path), never from
  /// passive selection listener events.
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
      _hasHandleRefinedSelection = true;
      _startBlock = blockIndex;
      _endBlock = blockIndex;
      _startOffset = start;
      _endOffset = end;
      for (final c in widget.controllers) {
        c.isGlobalSelected = false;
      }
      _updateBlockHighlights();
      for (final c in widget.controllers) {
        c.refresh();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _calculateHandlePositions());
    });
    widget.onSelectionChanged();
  }

  /// Recalculates handle positions after an external layout change (e.g. alignment
  /// applied to selected text). Must be called after the next frame so the
  /// RenderEditable has been laid out with the new textAlign/textDirection.
  void refreshPositions() {
    if (!hasSelection) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _calculateHandlePositions());
    });
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
      setState(() => _calculateHandlePositions());
    });
  }

  void _updateBlockHighlights() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return;
    }

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
    _calculateHandlePositions();
  }

  void _calculateHandlePositions() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return;
    }

    _handleStartPos = _getOffsetForPosition(
      _startBlock!,
      _startOffset!,
      endpointA: true,
    );
    _handleEndPos = _getOffsetForPosition(
      _endBlock!,
      _endOffset!,
      endpointA: false,
    );
  }

  Offset? _getOffsetForPosition(
    int blockIdx,
    int offset, {
    required bool endpointA,
  }) {
    if (blockIdx < 0 || blockIdx >= widget.blockKeys.length) return null;
    final context = widget.blockKeys[blockIdx].currentContext;
    if (context == null) return null;

    final renderObj = context.findRenderObject();
    if (renderObj == null) return null;

    // Use the actual RenderEditable so caret positions match rendered text
    // (where markup tags are hidden via zero-size style).
    final editable = _findRenderEditable(renderObj);

    // v4.1.0: Use _stackKey directly instead of findAncestorRenderObjectOfType<RenderStack>().
    // The ancestor search walks up the render tree and could find an intermediate
    // RenderStack (e.g. inside Scaffold internals) before reaching our Stack,
    // which would put coordinates in the wrong space. _stackKey always refers to
    // OUR Stack, guaranteed.
    final ourStack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (ourStack == null) return null;

    if (editable != null) {
      final controller = widget.controllers[blockIdx];
      final safeOffset = offset.clamp(0, controller.text.length).toInt();
      final caretOffset = editable.getLocalRectForCaret(
        TextPosition(offset: safeOffset, affinity: TextAffinity.downstream),
      );
      var endpointX = caretOffset.left;
      var endpointY = caretOffset.top + caretOffset.height / 2;
      final range = _normalizedRawRange();
      if (range != null) {
        final blockRtl = EditorTextGeometryService.resolveBlockRtl(
          widget.controllers.map((controller) => controller.text).toList(),
          blockIdx,
        );
        final isRangeStart = _endpointIsRangeStart(endpointA);
        final blockTextLength = controller.text.length;
        final selection = blockIdx == range.startBlock &&
                blockIdx == range.endBlock
            ? TextSelection(
                baseOffset: range.startOffset.clamp(0, blockTextLength).toInt(),
                extentOffset: range.endOffset.clamp(0, blockTextLength).toInt(),
              )
            : blockIdx == range.startBlock
                ? TextSelection(
                    baseOffset:
                        range.startOffset.clamp(0, blockTextLength).toInt(),
                    extentOffset: blockTextLength,
                  )
                : blockIdx == range.endBlock
                    ? TextSelection(
                        baseOffset: 0,
                        extentOffset:
                            range.endOffset.clamp(0, blockTextLength).toInt(),
                      )
                    : TextSelection(
                        baseOffset: 0, extentOffset: blockTextLength);
        final paintedEndpoint =
            MarkupRenderEditableGeometry.endpointForSelection(
          editable,
          selection,
          rawText: controller.text,
          isRangeStart: isRangeStart,
        );
        if (paintedEndpoint != null) {
          endpointX = paintedEndpoint.dx;
          endpointY = paintedEndpoint.dy;
        } else {
          final endpoints = editable.getEndpointsForSelection(selection);
          if (endpoints.isNotEmpty) {
            final endpoint = blockRtl
                ? _rtlSelectionEndpoint(endpoints, isRangeStart: isRangeStart)
                : (isRangeStart ? endpoints.first : endpoints.last);
            endpointX = endpoint.point.dx;
            endpointY = endpoint.point.dy;
          }
        }
      }
      return editable.localToGlobal(Offset(endpointX, endpointY),
          ancestor: ourStack);
    }

    // Fallback: use the block's top-left corner
    final box = renderObj as RenderBox;
    return box.localToGlobal(Offset.zero, ancestor: ourStack);
  }

  ({
    int startBlock,
    int startOffset,
    int endBlock,
    int endOffset,
  })? _normalizedRawRange() {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return null;
    }
    var sB = _startBlock!;
    var eB = _endBlock!;
    var sO = _startOffset!;
    var eO = _endOffset!;
    if (sB > eB || (sB == eB && sO > eO)) {
      final tB = sB;
      sB = eB;
      eB = tB;
      final tO = sO;
      sO = eO;
      eO = tO;
    }
    return (
      startBlock: sB,
      startOffset: _clampEndpointOffset(sB, sO),
      endBlock: eB,
      endOffset: _clampEndpointOffset(eB, eO),
    );
  }

  bool _endpointIsRangeStart(bool endpointA) {
    if (_startBlock == null ||
        _endBlock == null ||
        _startOffset == null ||
        _endOffset == null) {
      return endpointA;
    }
    final startBeforeEnd = _startBlock! < _endBlock! ||
        (_startBlock == _endBlock && _startOffset! <= _endOffset!);
    return startBeforeEnd ? endpointA : !endpointA;
  }

  TextSelectionPoint _rtlSelectionEndpoint(
    List<TextSelectionPoint> endpoints, {
    required bool isRangeStart,
  }) {
    const lineTolerance = 4.0;
    if (endpoints.length == 1) return endpoints.single;
    final sortedByLine = [...endpoints]..sort((a, b) {
        final yCompare = a.point.dy.compareTo(b.point.dy);
        if (yCompare != 0) return yCompare;
        return a.point.dx.compareTo(b.point.dx);
      });
    final anchorY =
        isRangeStart ? sortedByLine.first.point.dy : sortedByLine.last.point.dy;
    final sameLine = sortedByLine
        .where(
            (endpoint) => (endpoint.point.dy - anchorY).abs() <= lineTolerance)
        .toList();
    if (sameLine.isEmpty) {
      return isRangeStart ? sortedByLine.first : sortedByLine.last;
    }
    sameLine.sort((a, b) => a.point.dx.compareTo(b.point.dx));
    return isRangeStart ? sameLine.last : sameLine.first;
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

  void _handleUpdate(Offset globalPos, bool isStart) {
    _enterRefineMode();

    int? targetBlock;
    TextPosition? targetPosition;
    double? targetDistance;
    bool targetIsInside = false;

    for (int i = 0; i < widget.blockKeys.length; i++) {
      final renderObj = widget.blockKeys[i].currentContext?.findRenderObject();
      if (renderObj == null) continue;
      final box = renderObj as RenderBox;

      final boxLocal = box.globalToLocal(globalPos);
      final inside = boxLocal.dy >= 0 && boxLocal.dy <= box.size.height;
      final distance = inside
          ? 0.0
          : boxLocal.dy < 0
              ? -boxLocal.dy
              : boxLocal.dy - box.size.height;
      if (targetDistance != null &&
          (targetIsInside || !inside) &&
          distance >= targetDistance) {
        continue;
      }

      // Use the actual RenderEditable for accurate hit-testing
      final editable = _findRenderEditable(renderObj);
      TextPosition pos;
      if (boxLocal.dy < 0) {
        pos = const TextPosition(offset: 0);
      } else if (boxLocal.dy > box.size.height) {
        pos = TextPosition(offset: widget.controllers[i].text.length);
      } else if (editable != null) {
        // v4.1.1: Pass globalPos directly — getPositionForPoint expects a
        // GLOBAL coordinate and converts internally with globalToLocal().
        // The previous code converted to local first, causing a second
        // globalToLocal() call inside getPositionForPoint that shifted y
        // by the widget's screen offset, always returning a line-1 result.
        pos = editable.getPositionForPoint(globalPos);
      } else {
        // Fallback: beginning or end of block
        pos = TextPosition(
            offset: boxLocal.dx < box.size.width / 2
                ? 0
                : widget.controllers[i].text.length);
      }
      targetBlock = i;
      targetPosition = pos;
      targetDistance = distance;
      targetIsInside = inside;
      if (inside) break;
      continue;
    }

    final block = targetBlock;
    final pos = targetPosition;
    if (block == null || pos == null) return;

    setState(() {
      _isSelecting = true;
      _hasHandleRefinedSelection = true;
      if (isStart) {
        if (_startBlock != block) HapticFeedback.selectionClick();
        _startBlock = block;
        _startOffset =
            pos.offset.clamp(0, widget.controllers[block].text.length).toInt();
      } else {
        if (_endBlock != block) HapticFeedback.selectionClick();
        _endBlock = block;
        _endOffset =
            pos.offset.clamp(0, widget.controllers[block].text.length).toInt();
      }
      _updateBlockHighlights();
      for (final c in widget.controllers) {
        c.refresh();
      }
    });
    // Recalculate handle positions after the frame so caret coords
    // reflect the new selection highlight layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _calculateHandlePositions());
    });
    widget.onSelectionChanged();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        final start = hasSelection ? _handleStartPos : null;
        final end = hasSelection ? _handleEndPos : null;
        return Stack(
          key: _stackKey,
          children: [
            widget.child,
            if (start != null &&
                (_draggingStart || _isHandleVisibleInViewport(start)))
              _buildHandle(start, true),
            if (end != null &&
                (_draggingEnd || _isHandleVisibleInViewport(end)))
              _buildHandle(end, false),
          ],
        );
      },
    );
  }

  bool _isHandleVisibleInViewport(Offset pos) {
    const margin = 18.0;
    return pos.dy >= -margin &&
        pos.dy <= _stackSize.height + margin &&
        pos.dx >= -40 &&
        pos.dx <= _stackSize.width + 40;
  }

  Widget _buildHandle(Offset pos, bool isStart) {
    return Positioned(
      left: (pos.dx - 16)
          .clamp(0.0, _stackSize.width > 40 ? _stackSize.width - 40 : 0.0),
      top: (pos.dy - 18)
          .clamp(0.0, _stackSize.height > 56 ? _stackSize.height - 56 : 0.0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          _enterRefineMode();
          // v4.0.9: Convert the handle's Stack-local caret position to GLOBAL
          // coordinates HERE (layout is guaranteed valid from the previous frame).
          // Subsequent onPanUpdate calls just add the finger delta to this global
          // caret origin, so the caret — not the touch-point — drives
          // _handleUpdate.  This eliminates the line-1 snap that occurred when
          // the user's finger landed at the top of the 56-px hit area (18 px
          // above the caret) and the raw touch y was mapped to line 1 instead.
          final stackBox =
              _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final logicalStackLocal = isStart ? _handleStartPos : _handleEndPos;
          final caretGlobal = (stackBox != null && logicalStackLocal != null)
              ? stackBox.localToGlobal(logicalStackLocal)
              : null;
          setState(() {
            if (isStart) {
              _draggingStart = true;
            } else {
              _draggingEnd = true;
            }
            _panStartGlobal = details.globalPosition;
            _panStartHandleGlobal = caretGlobal;
          });
        },
        onPanUpdate: (details) {
          final caretStart = _panStartHandleGlobal;
          final panStart = _panStartGlobal;
          if (caretStart != null && panStart != null) {
            final delta = details.globalPosition - panStart;
            _handleUpdate(caretStart + delta, isStart);
          } else {
            _handleUpdate(details.globalPosition, isStart);
          }
        },
        onPanEnd: (_) => setState(() {
          if (isStart) {
            _draggingStart = false;
          } else {
            _draggingEnd = false;
          }
          _panStartGlobal = null;
          _panStartHandleGlobal = null;
        }),
        child: Container(
          width: 40,
          height: 56,
          color: Colors.transparent, // Hit test area
          child: Center(
            child: Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFFBF00),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
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
