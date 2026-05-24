part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlayHandles on GlobalSelectionOverlayState {
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
    if (local.dx < -_hardExitMargin ||
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
      // Near top - scroll up
      final factor =
          ((_autoScrollZone - local.dy) / _autoScrollZone).clamp(0.0, 1.0);
      speed = -_autoScrollMax * factor.toDouble();
    } else if (local.dy > height - _autoScrollZone) {
      // Near bottom - scroll down
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
    _setOverlayState(() {
      _ignoreBodyDragUntilPointerUp = true;
      _sessionMode = SelectionSessionMode.handleDrag;
      _pointerState = pointerState;
    });
  }

  void _stopAutoScroll() {
    _handleDrag?.cancelAutoScroll();
  }

  void _stopBodyAutoScroll() {
    _bodyAutoScrollTimer?.cancel();
    _bodyAutoScrollTimer = null;
  }

  void _resetDragState() {
    _stopBodyAutoScroll();
    _latestBodyDragGlobal = null;
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
    _setOverlayState(() {
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
}
