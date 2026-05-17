part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlayBodyDrag on GlobalSelectionOverlayState {
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
    _latestBodyDragGlobal = globalPos;
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
    _latestBodyDragGlobal = globalPos;
    if (!_bodyDragActive) {
      final currentBlock = _blockAtPosition(globalPos);
      final crossed = currentBlock != null &&
          _candidateBlock != null &&
          currentBlock != _candidateBlock;
      final emptyToBlock = _candidateBlock == null && currentBlock != null;
      final edgeDrag = _shouldStartBodyEdgeDrag(globalPos);
      if (!crossed && !emptyToBlock && !edgeDrag) return;

      _bodyDragActive = true;
      _enterRefineMode();

      // Anchor priority for the start of the global selection:
      //  1. Cached char offset captured at pointer-down (most robust â€” frozen
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
      _updateBodyAutoScroll(globalPos);
      return;
    }
    _handleUpdate(globalPos, false);
    _updateBodyAutoScroll(globalPos);
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

  bool _shouldStartBodyEdgeDrag(Offset globalPos) {
    if (_handleDrag != null ||
        _candidateBlock == null ||
        _candidateOffset == null ||
        _candidatePos == null) {
      return false;
    }
    if ((globalPos - _candidatePos!).distance <= 4.0) return false;
    if (_pointerStateFor(globalPos) != SelectionPointerState.edgeZone) {
      return false;
    }
    return _bodyScrollSpeed(globalPos) != 0;
  }

  double _bodyScrollSpeed(Offset globalPos) {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return 0;
    final speed = _edgeScrollSpeed(globalPos);
    if (speed == 0) return 0;
    final next = (sc.offset + speed)
        .clamp(sc.position.minScrollExtent, sc.position.maxScrollExtent)
        .toDouble();
    return next == sc.offset ? 0 : speed;
  }

  void _updateBodyAutoScroll(Offset globalPos) {
    if (_handleDrag != null || !_bodyDragActive) {
      _stopBodyAutoScroll();
      return;
    }
    _latestBodyDragGlobal = globalPos;
    if (_pointerStateFor(globalPos) == SelectionPointerState.edgeZone &&
        _bodyScrollSpeed(globalPos) != 0) {
      _ensureBodyAutoScroll();
    } else {
      _stopBodyAutoScroll();
    }
  }

  void handleBodyPointerExitedEditor(Offset globalPos) {
    if (!_bodyDragActive || _handleDrag != null) return;
    _latestBodyDragGlobal = globalPos;
    _updateBodyAutoScroll(globalPos);
  }

  void _ensureBodyAutoScroll() {
    if (_bodyAutoScrollTimer != null) return;
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) return;
    _bodyAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (!mounted || !_bodyDragActive || _handleDrag != null) {
          _stopBodyAutoScroll();
          return;
        }
        final pointer = _latestBodyDragGlobal;
        if (pointer == null || !sc.hasClients) {
          _stopBodyAutoScroll();
          return;
        }
        if (_pointerStateFor(pointer) != SelectionPointerState.edgeZone) {
          _stopBodyAutoScroll();
          return;
        }
        final speed = _bodyScrollSpeed(pointer);
        if (speed == 0) {
          _stopBodyAutoScroll();
          return;
        }
        final next = (sc.offset + speed)
            .clamp(sc.position.minScrollExtent, sc.position.maxScrollExtent)
            .toDouble();
        sc.jumpTo(next);
        _handleUpdate(pointer, false);
        refreshPositions();
      },
    );
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
}
