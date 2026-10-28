part of 'teleprompter_screen.dart';

class _PresenterViewportAnchor {
  const _PresenterViewportAnchor(this.script, this.index, this.rowOffset);
  final Script script;
  final int index;
  // Preserve where the reading line cuts this word, not the old pixel offset.
  final double rowOffset;
}

extension _TeleprompterViewportAnchorParts on _TeleprompterScreenState {
  Future<void> _togglePresenterFullscreen() async {
    await _setPresenterFullscreen(!_presenterFullscreen);
    _showWindowsControlsFromHotZone();
  }

  Future<void> _setPresenterFullscreen(bool enabled) async {
    final pending = _fullscreenCompletion;
    if (pending != null) {
      await pending.future;
      if (mounted) await _setPresenterFullscreen(enabled);
      return;
    }
    if (enabled == _presenterFullscreen) return;
    final completion = Completer<void>();
    _fullscreenCompletion = completion;
    _captureViewportAnchor();
    try {
      final applied = await PresenterFullscreenService.setEnabled(enabled);
      if (!mounted) {
        if (applied) await PresenterFullscreenService.setEnabled(false);
        return;
      }
      _setTeleprompterState(() => _presenterFullscreen = applied);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'presenter.fullscreen',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fullscreen is unavailable.')),
        );
      }
    } finally {
      _fullscreenCompletion = null;
      completion.complete();
      if (mounted) _scheduleViewportAnchorRestore();
    }
  }

  void _captureViewportAnchor() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    _viewportGeometryPending = true;
    _viewportGeometryGeneration++;
    // Until new boxes have actually been laid out, no automatic target can
    // qualify against stale coordinates. This does not reset speech/progress.
    _sessionOwner.setVisibleWordWindow(null, null);
    if (_viewportAnchor != null) {
      _scheduleViewportAnchorRestore();
      return;
    }
    final script = ref.read(scriptProvider);
    final settled = _settledViewportAnchor;
    if (settled != null &&
        identical(script, settled.script) &&
        _settledViewportOffset != null &&
        (_scrollController.offset - _settledViewportOffset!).abs() < .1) {
      // A wider line can start earlier than the original anchor. Reuse the
      // same word through repeated fullscreen/windowed toggles until actual
      // reading or user motion changes the viewport; otherwise rows drift.
      _viewportAnchor = settled;
      _cancelSmoothScroll();
      _scheduleViewportAnchorRestore();
      return;
    }
    final index = _wordIndexNearestReadingLine();
    if (script == null || index == null) {
      _viewportGeometryPending = false;
      _scheduleVisibleWordWindowSync(force: true);
      return;
    }
    final box = _boxForWordIndex(index);
    if (box == null || !box.attached || !box.hasSize || box.size.height <= 0) {
      _viewportGeometryPending = false;
      _scheduleVisibleWordWindowSync(force: true);
      return;
    }
    final axis = _presenterScrollAxis();
    final offset =
        (_presenterBoxAxisLeading(box, axis) -
            _presenterReadingTargetAxis(axis)) *
        axis.direction;
    _viewportAnchor = _PresenterViewportAnchor(
      script,
      index,
      offset / box.size.height,
    );
    // Pixel targets from the old wrapping are no longer meaningful.
    _cancelSmoothScroll();
    _activeManualCorrectionTimer?.cancel();
    _activeManualCorrection = false;
    _userBrowsingWhileStopped = false;
    _lastPresenterUserScrollSignalAt = null;
    _scheduleViewportAnchorRestore();
  }

  void _handlePresenterViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0) return; // Minimized window.
    final previous = _lastPresenterViewportSize;
    if (previous != null && previous != size) {
      _captureViewportAnchor();
      _scheduleViewportAnchorRestore();
    }
    _lastPresenterViewportSize = size;
  }

  void _scheduleViewportAnchorRestore() {
    if (_viewportAnchor == null || _viewportRestoreScheduled) return;
    _viewportRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportRestoreScheduled = false;
      if (!mounted) return;
      _restoreViewportAnchor();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _restoreViewportAnchor() {
    final anchor = _viewportAnchor;
    if (anchor == null || !_scrollController.hasClients) return;
    if (!identical(anchor.script, ref.read(scriptProvider))) {
      _viewportAnchor = null;
      _viewportGeometryPending = false;
      _scheduleVisibleWordWindowSync(force: true);
      return;
    }
    final size = MediaQuery.sizeOf(context);
    if (size.width <= 0 || size.height <= 0) return;
    final box = _boxForWordIndex(anchor.index);
    if (box == null || !box.attached || !box.hasSize) return;
    final axis = _presenterScrollAxis();
    final delta =
        (_presenterBoxAxisLeading(box, axis) -
                _presenterReadingTargetAxis(axis)) *
            axis.direction -
        anchor.rowOffset * box.size.height;
    final position = _scrollController.position;
    _scrollTarget = (_scrollController.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _suppressPresenterProgrammaticPositionCommit(immediate: true);
    if ((_scrollController.offset - _scrollTarget).abs() > 0.1) {
      _scrollController.jumpTo(_scrollTarget);
    }
    // jumpTo invalidates viewport layout; its boxes are not trustworthy until
    // the NEXT frame. Never publish the pre-jump geometry as the new viewport.
    final generation = ++_viewportGeometryGeneration;
    _viewportGeometryPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _viewportGeometryGeneration) return;
      _viewportGeometryPending = false;
      _syncVisibleWordWindow(force: true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    _viewportSettleTimer?.cancel();
    _viewportSettleTimer = Timer(const Duration(milliseconds: 180), () {
      _settledViewportAnchor = _viewportAnchor;
      if (_scrollController.hasClients) {
        _settledViewportOffset = _scrollController.offset;
      }
      _viewportAnchor = null;
      if (mounted) _scheduleVisibleWordWindowSync(force: true);
    });
  }
}
