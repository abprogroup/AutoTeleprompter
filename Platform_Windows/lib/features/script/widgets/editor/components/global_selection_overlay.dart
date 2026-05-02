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
  Size _stackSize = Size.zero;

  // Delta-drag state: track finger start (global) and the handle's caret start
  // position (also global, converted at pan-start while layout is valid).
  Offset? _panStartGlobal;
  Offset? _panStartHandleGlobal; // caret global position at the moment of pan start
  final GlobalKey _stackKey = GlobalKey();

  // Body-pointer candidate state: pointer-down does NOT immediately start a
  // global selection. We record the origin and the block it landed in, then
  // only activate global selection if the pointer drags into a DIFFERENT
  // block. This lets click + in-block drag stay native (TextField handles it),
  // and only cross-block drags become multi-paragraph selections.
  Offset? _candidatePos;
  int? _candidateBlock;
  int? _anchorBlock;
  int? _anchorOffset;
  bool _bodyDragActive = false;

  /// True when every block is wholly selected (post Select All, pre refine).
  bool get _isWholeScriptSelected =>
      widget.controllers.isNotEmpty &&
      widget.controllers.every((c) => c.isGlobalSelected);

  void clearSelection() {
    if (!_isSelecting) return;
    setState(() {
      _isSelecting = false;
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

  void selectAll() {
    if (widget.controllers.isEmpty) return;
    setState(() {
      _isSelecting = true;
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

  bool get hasSelection => _isSelecting && _startBlock != null && _endBlock != null;

  /// Returns the block index whose render box contains [globalPos], or null.
  int? _blockAtPosition(Offset globalPos) {
    for (int i = 0; i < widget.blockKeys.length; i++) {
      final box = widget.blockKeys[i].currentContext?.findRenderObject() as RenderBox?;
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

  /// Body pointer-down: just record the candidate. Do NOT activate global
  /// selection — that happens only when the pointer leaves the starting block.
  void startDragging(Offset globalPos) {
    _candidatePos = globalPos;
    _candidateBlock = _blockAtPosition(globalPos);
    _bodyDragActive = false;
  }

  /// Body pointer-move: activate global selection iff the pointer has crossed
  /// into a different block than where the gesture started. Once active,
  /// extend the selection from the original origin to the current position.
  void updateDragging(Offset globalPos) {
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

      // Resolve the anchor ONCE at the moment of activation
      final originBlock = _candidateBlock;
      if (originBlock != null) {
        final key = widget.blockKeys[originBlock];
        final context = key.currentContext;
        final editable = _findRenderEditable(context?.findRenderObject());
        if (editable != null) {
          final blockGlobalPos = editable.localToGlobal(Offset.zero);
          final pos =
              editable.getPositionForPoint(_candidatePos! - blockGlobalPos);
          _anchorBlock = originBlock;
          _anchorOffset = pos.offset;
        }
      }

      setState(() {
        _isSelecting = true;
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
    _candidatePos = null;
    _candidateBlock = null;
    _bodyDragActive = false;
    // Selection persists after drag
  }

  void _handleUpdate(Offset globalPos, bool isStart) {
    final RenderBox? overlayBox =
        context.findRenderObject() as RenderBox?;
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
            final blockGlobalPos = editable.localToGlobal(Offset.zero);
            final pos = editable.getPositionForPoint(globalPos - blockGlobalPos);

            setState(() {
              if (isStart) {
                _startBlock = bestBlock;
                _startOffset = pos.offset;
              } else {
                _endBlock = bestBlock;
                _endOffset = pos.offset;
              }
              _updateControllers();
            });
            widget.onSelectionChanged();
          }
        }
      }
    }
  }

  void _updateControllers() {
    if (_startBlock == null || _endBlock == null) return;

    final low = _startBlock! < _endBlock! ? _startBlock! : _endBlock!;
    final high = _startBlock! > _endBlock! ? _startBlock! : _endBlock!;
    final lowOffset =
        (_startBlock! < _endBlock! ? _startOffset : _endOffset) ?? 0;
    final highOffset =
        (_startBlock! > _endBlock! ? _startOffset : _endOffset) ?? 0;

    for (int i = 0; i < widget.controllers.length; i++) {
      final c = widget.controllers[i];
      if (i < low || i > high) {
        c.isGlobalSelected = false;
        c.externalSelection = null;
      } else if (i > low && i < high) {
        c.isGlobalSelected = true;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: c.text.length);
      } else if (i == low && i == high) {
        c.isGlobalSelected = false;
        final start = lowOffset < highOffset ? lowOffset : highOffset;
        final end = lowOffset > highOffset ? lowOffset : highOffset;
        c.externalSelection =
            TextSelection(baseOffset: start, extentOffset: end);
      } else if (i == low) {
        c.isGlobalSelected = false;
        c.externalSelection = TextSelection(
            baseOffset: lowOffset, extentOffset: c.text.length);
      } else if (i == high) {
        c.isGlobalSelected = false;
        c.externalSelection =
            TextSelection(baseOffset: 0, extentOffset: highOffset);
      }
      c.refresh();
    }
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
      if (c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed) {
        _startOffset = c.externalSelection!.start;
      }
    }
    if (_endBlock! < controllers.length) {
      final c = controllers[_endBlock!];
      if (c.externalSelection != null && c.externalSelection!.isValid && !c.externalSelection!.isCollapsed) {
        _endOffset = c.externalSelection!.end;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _calculateHandlePositions());
    });
  }

  void _updateBlockHighlights() {
    if (_startBlock == null || _endBlock == null || _startOffset == null || _endOffset == null) return;

    // Ensure start is before end
    int sB = _startBlock!, eB = _endBlock!;
    int sO = _startOffset!, eO = _endOffset!;
    if (sB > eB || (sB == eB && sO > eO)) {
      final tB = sB; sB = eB; eB = tB;
      final tO = sO; sO = eO; eO = tO;
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
        c.externalSelection = TextSelection(baseOffset: sO, extentOffset: c.text.length);
      } else if (i == eB) {
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: eO);
      } else {
        c.externalSelection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    }
    _calculateHandlePositions();
  }

  void _calculateHandlePositions() {
    if (_startBlock == null || _endBlock == null || _startOffset == null || _endOffset == null) return;
    
    _handleStartPos = _getOffsetForPosition(_startBlock!, _startOffset!);
    _handleEndPos = _getOffsetForPosition(_endBlock!, _endOffset!);
  }

  Offset? _getOffsetForPosition(int blockIdx, int offset) {
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
      // v4.1.0: Use downstream affinity so a position at a line-wrap boundary
      // resolves to the START of the next line, not the end of the previous line.
      // Without this, handles at wrap boundaries always snapped back to line 1.
      final caretOffset = editable.getLocalRectForCaret(
        TextPosition(offset: offset, affinity: TextAffinity.downstream),
      );
      return editable.localToGlobal(caretOffset.topLeft, ancestor: ourStack);
    }

    // Fallback: use the block's top-left corner
    final box = renderObj as RenderBox;
    return box.localToGlobal(Offset.zero, ancestor: ourStack);
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        // Fall back to viewport edges so handles are always reachable,
        // even if the first/last block isn't currently rendered.
        final start = hasSelection
            ? (_handleStartPos ?? Offset(12, _startBlock! < (_endBlock ?? 0) ? -20 : constraints.maxHeight + 20))
            : null;
        final end = hasSelection
            ? (_handleEndPos ?? Offset(12, _endBlock! < (_startBlock ?? 0) ? -20 : constraints.maxHeight + 20))
            : null;
        return Stack(
          key: _stackKey,
          children: [
            widget.child,
            if (start != null) _buildHandle(start, true),
            if (end != null) _buildHandle(end, false),
          ],
        );
      },
    );
  }

  Widget _buildHandle(Offset pos, bool isStart) {
    return Positioned(
      left: (pos.dx - 16).clamp(0.0, _stackSize.width > 40 ? _stackSize.width - 40 : 0.0),
      top: (pos.dy - 18).clamp(0.0, _stackSize.height > 56 ? _stackSize.height - 56 : 0.0),
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
          final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
          final logicalStackLocal = isStart ? _handleStartPos : _handleEndPos;
          final caretGlobal = (stackBox != null && logicalStackLocal != null)
              ? stackBox.localToGlobal(logicalStackLocal)
              : null;
          setState(() {
            if (isStart) _draggingStart = true; else _draggingEnd = true;
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
          if (isStart) _draggingStart = false; else _draggingEnd = false;
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
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
