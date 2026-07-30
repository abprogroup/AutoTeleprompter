part of 'global_selection_overlay.dart';

extension _GlobalSelectionOverlayHandlesParts on GlobalSelectionOverlayState {
  SelectionPointerState _pointerStateFor(Offset globalHandlePos) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null) return SelectionPointerState.stale;
    final local = stack.globalToLocal(globalHandlePos);
    final height = _stackSize.height;
    if (local.dx < -GlobalSelectionOverlayState._hardExitMargin ||
        local.dx >
            _stackSize.width + GlobalSelectionOverlayState._hardExitMargin) {
      return SelectionPointerState.outside;
    }
    if (local.dy < GlobalSelectionOverlayState._autoScrollZone ||
        local.dy > height - GlobalSelectionOverlayState._autoScrollZone) {
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
    if (local.dy < GlobalSelectionOverlayState._autoScrollZone) {
      // Near top - scroll up
      final factor = ((GlobalSelectionOverlayState._autoScrollZone - local.dy) /
              GlobalSelectionOverlayState._autoScrollZone)
          .clamp(0.0, 1.0);
      speed = -GlobalSelectionOverlayState._autoScrollMax * factor.toDouble();
    } else if (local.dy >
        height - GlobalSelectionOverlayState._autoScrollZone) {
      // Near bottom - scroll down
      final factor =
          ((local.dy - (height - GlobalSelectionOverlayState._autoScrollZone)) /
                  GlobalSelectionOverlayState._autoScrollZone)
              .clamp(0.0, 1.0);
      speed = GlobalSelectionOverlayState._autoScrollMax * factor.toDouble();
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

  void _armStalePointerTimer() {
    final session = _handleDrag;
    if (session == null) return;
    session.cancelStale();
    session.staleTimer =
        Timer(GlobalSelectionOverlayState._stalePointerTimeout, () {
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
    setState(() {
      _ignoreBodyDragUntilPointerUp = suppressBodyDragUntilPointerUp;
      _sessionMode = hasSelection
          ? SelectionSessionMode.overlaySelection
          : SelectionSessionMode.none;
      _pointerState = pointerState;
    });
  }
}
