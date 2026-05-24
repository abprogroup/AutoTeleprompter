part of 'global_selection_overlay.dart';

extension GlobalSelectionOverlayBuild on GlobalSelectionOverlayState {
  Widget _buildOverlay(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        // Only show a handle when its block is currently rendered (position
        // known). If the block has scrolled offscreen, _handleStartPos /
        // _handleEndPos is null. We hide the handle instead of clamping it
        // to a viewport edge - a handle floating at an unrelated edge is
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
          // caret origin, so the caret - not the touch-point - drives
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
          _setOverlayState(() {
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
