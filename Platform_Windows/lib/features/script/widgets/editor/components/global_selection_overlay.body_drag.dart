part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlayBodyDrag on GlobalSelectionOverlayState {
  bool startDragging(Offset globalPos) {
    if (_handleDrag != null &&
        (_pointerState == SelectionPointerState.outside ||
            _pointerState == SelectionPointerState.stale)) {
      _endHandleDrag(
        reason: 'new-pointer',
        pointerState: SelectionPointerState.inside,
        suppressBodyDragUntilPointerUp: false,
      );
    }
    if (_ignoreBodyDragUntilPointerUp) return false;

    final endpoint = _endpointAtGlobalPosition(globalPos, allowNearest: false);
    _candidatePos = globalPos;
    _latestBodyDragGlobal = globalPos;
    _candidateBlock = endpoint?.block;
    _candidateOffset = endpoint?.offset;
    _bodyDragActive = false;
    _lastBodyDragFocusTrace = null;
    _debugSelectionEvent(
      'dragStart block=${_candidateBlock ?? "-"} '
      'offset=${_candidateOffset ?? "-"}',
    );
    return endpoint != null;
  }

  /// Body pointer-move: same-block drags stay native-owned until pointer-up.
  /// Overlay ownership begins only once the gesture clearly crosses blocks,
  /// enters a block from outside editable text, or reaches a real scroll edge.
  void updateDragging(Offset globalPos) {
    if (_ignoreBodyDragUntilPointerUp || _candidatePos == null) return;
    _latestBodyDragGlobal = globalPos;

    if (!_bodyDragActive) {
      final currentEndpoint =
          _endpointAtGlobalPosition(globalPos, allowNearest: false);
      final currentBlock = currentEndpoint?.block;
      final crossed = currentEndpoint != null &&
          _candidateBlock != null &&
          currentBlock != _candidateBlock;
      final outsideToBlock = _candidateBlock == null && currentEndpoint != null;
      final edgeDrag = _shouldStartBodyEdgeDrag(
        globalPos,
        currentBlock: currentBlock,
      );
      if (!crossed && !outsideToBlock && !edgeDrag) return;

      final anchor = _frozenBodyDragAnchor() ??
          currentEndpoint ??
          _endpointAtGlobalPosition(_candidatePos!, allowNearest: true);
      final focus = currentEndpoint ??
          _endpointAtGlobalPosition(globalPos, allowNearest: true);
      if (anchor == null || focus == null) return;

      _enterRefineMode();
      _setOverlayState(() {
        _bodyDragActive = true;
        _isSelecting = true;
        _sessionMode = SelectionSessionMode.overlaySelection;
        _pointerState = SelectionPointerState.inside;
        _focusEndpointIsStart = false;
        _startBlock = anchor.block;
        _startOffset = anchor.offset;
        _endBlock = focus.block;
        _endOffset = focus.offset;
        _updateControllers();
      });
      _lastBodyDragFocusTrace = focus;
      _afterEndpointUpdate(
        debugReason: 'dragActivate anchor=$anchor focus=$focus '
            'crossed=$crossed outsideToBlock=$outsideToBlock edge=$edgeDrag',
      );
      _updateBodyAutoScroll(globalPos);
      return;
    }

    final focusChanged = _handleUpdate(
      globalPos,
      false,
      allowNearest: false,
    );
    if (focusChanged) {
      final focus = SelectionEndpoint(block: _endBlock!, offset: _endOffset!);
      if (_lastBodyDragFocusTrace?.block != focus.block) {
        _lastBodyDragFocusTrace = focus;
        _debugSelectionEvent('dragUpdate focus=$focus');
      }
    }
    _updateBodyAutoScroll(globalPos);
  }

  bool endDragging() {
    final overlayOwnedGesture = _bodyDragActive || _handleDrag != null;
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
    _debugSelectionEvent('dragEnd overlayOwned=$overlayOwnedGesture');
    return overlayOwnedGesture;
  }

  bool _shouldStartBodyEdgeDrag(
    Offset globalPos, {
    required int? currentBlock,
  }) {
    if (_handleDrag != null ||
        _candidateBlock == null ||
        _candidateOffset == null ||
        _candidatePos == null) {
      return false;
    }
    final delta = globalPos - _candidatePos!;
    if (delta.distance <= 4.0 || delta.dy.abs() <= 18.0) return false;
    if (currentBlock == _candidateBlock) return false;
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
        _handleUpdate(pointer, false, allowNearest: true);
        refreshPositions();
      },
    );
  }

  bool _handleUpdate(
    Offset globalPos,
    bool isStart, {
    bool allowNearest = true,
  }) {
    final changed = _applyEndpointUpdate(
      globalPos,
      isStart: isStart,
      allowNearest: allowNearest,
    );
    if (changed) _afterEndpointUpdate();
    return changed;
  }

  bool _applyEndpointUpdate(
    Offset globalPos, {
    required bool isStart,
    required bool allowNearest,
  }) {
    final endpoint = _endpointAtGlobalPosition(
      globalPos,
      allowNearest: allowNearest,
    );
    if (endpoint == null) return false;
    final same = isStart
        ? _startBlock == endpoint.block && _startOffset == endpoint.offset
        : _endBlock == endpoint.block && _endOffset == endpoint.offset;
    if (same) return false;

    _setOverlayState(() {
      if (isStart) {
        _focusEndpointIsStart = true;
        _startBlock = endpoint.block;
        _startOffset = endpoint.offset;
      } else {
        _focusEndpointIsStart = false;
        _endBlock = endpoint.block;
        _endOffset = endpoint.offset;
      }
      _updateControllers();
    });
    return true;
  }

  SelectionEndpoint? _frozenBodyDragAnchor() {
    if (_candidateBlock == null || _candidateOffset == null) return null;
    return SelectionEndpoint(
      block: _candidateBlock!,
      offset: _clampEndpointOffset(_candidateBlock!, _candidateOffset!),
    );
  }

  SelectionEndpoint? _endpointAtGlobalPosition(
    Offset globalPos, {
    required bool allowNearest,
  }) {
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return null;
    final localPos = overlayBox.globalToLocal(globalPos);

    int? bestBlock;
    double minDistance = double.infinity;
    for (var i = 0; i < widget.blockKeys.length; i++) {
      final box =
          widget.blockKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final blockOffset = box.localToGlobal(Offset.zero);
      final localInOverlay = overlayBox.globalToLocal(blockOffset);
      final rect = localInOverlay & box.size;
      if (rect.contains(localPos)) {
        bestBlock = i;
        break;
      }
      if (allowNearest) {
        final dist = (rect.center - localPos).distance;
        if (dist < minDistance) {
          minDistance = dist;
          bestBlock = i;
        }
      }
    }
    if (bestBlock == null) return null;

    final blockContext = widget.blockKeys[bestBlock].currentContext;
    final renderObj = blockContext?.findRenderObject();
    if (renderObj == null) return null;
    final editable = _findRenderEditable(renderObj);
    if (editable == null) return null;
    final pos = editable.getPositionForPoint(globalPos);
    final offset =
        pos.offset.clamp(0, widget.controllers[bestBlock].text.length).toInt();
    return SelectionEndpoint(block: bestBlock, offset: offset);
  }

  void _afterEndpointUpdate({String? debugReason}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) refreshPositions();
    });
    widget.onSelectionChanged();
    if (debugReason != null) {
      _debugSelectionEvent(debugReason);
    }
  }
}
