part of 'teleprompter_screen.dart';

extension _TeleprompterManualScrollParts on _TeleprompterScreenState {
  void _startManualScroll({bool backward = false}) {
    if (!_scrollController.hasClients) return;
    _scrollingBackward = backward;
    _setTeleprompterState(() => _manualScrolling = true);
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();

    // 60fps smooth pixel scroll
    _manualScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_scrollController.hasClients) return;
      final settings = ref.read(settingsProvider);

      // Speed can be negative for backward scrolling
      final sttState = ref.read(teleprompterProvider);
      final activeManualOverride =
          PresenterInputLockService.allowActiveManualScroll(
        settingEnabled: settings.allowScrollDuringActiveSession,
        isListening: sttState.isListening,
        isStarting: sttState.isStarting,
      );
      final speed = settings.scrollMode == 'manual' || activeManualOverride
          ? settings.scrollSpeed
          : 100.0;
      if (speed == 0) return;

      // pixels per tick: speed(wpm) x 3px x 16ms/1000ms
      final pxPerTick = speed.abs() * 3.0 * 16.0 / 1000.0;
      final isBackward = speed < 0;
      final delta = isBackward ? -pxPerTick : pxPerTick;

      final next = _scrollController.offset + delta;
      final max = _scrollController.position.maxScrollExtent;

      if (!isBackward && next >= max) {
        _scrollController.jumpTo(max);
        _stopManualScroll();
        return;
      }
      if (isBackward && next <= 0) {
        _scrollController.jumpTo(0);
        _stopManualScroll();
        return;
      }
      _scrollController.jumpTo(next.clamp(0.0, max));
    });

    // Update highlighted word at 5fps (cheap: only scans nearby keys)
    _wordTrackTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _updateManualWordIndex();
    });
  }

  void _updateManualWordIndex() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_scrollController.offset <= 1.0) {
      final script = ref.read(scriptProvider);
      if (_manualWordIndex != 0) {
        _setTeleprompterState(() => _manualWordIndex = 0);
      }
      if (script != null &&
          ref.read(teleprompterProvider).confirmedWordIndex != 0) {
        ref
            .read(teleprompterProvider.notifier)
            .jumpToPosition(0, script: script);
      }
      return;
    }
    var bestIndex = _wordIndexNearestReadingLine() ?? _manualWordIndex;
    final settings = ref.read(settingsProvider);

    if (_manualScrolling && settings.scrollMode == 'manual') {
      final speed = settings.scrollSpeed;
      if (speed > 0 && bestIndex < _manualWordIndex) {
        bestIndex = _manualWordIndex;
      } else if (speed < 0 && bestIndex > _manualWordIndex) {
        bestIndex = _manualWordIndex;
      }
    }

    if (bestIndex != _manualWordIndex) {
      _setTeleprompterState(() => _manualWordIndex = bestIndex);
      final script = ref.read(scriptProvider);
      if (script != null && script.words.isNotEmpty) {
        ref
            .read(teleprompterProvider.notifier)
            .jumpToPosition(bestIndex, script: script);
      }
    }
  }

  int? _wordIndexNearestReadingLine() {
    final script = ref.read(scriptProvider);
    if (script == null ||
        script.words.isEmpty ||
        !_scrollController.hasClients ||
        _wordKeys.isEmpty) {
      return null;
    }
    final axis = _presenterScrollAxis();
    final targetAxis = _presenterReadingTargetAxis(axis);

    int? bestIndex;
    double bestDist = double.infinity;
    final maxIndex = _wordKeys.length < script.words.length
        ? _wordKeys.length
        : script.words.length;

    for (var i = 0; i < maxIndex; i++) {
      final word = script.words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final wordAxis = _presenterBoxAxisLeading(box, axis);
      final dist = (wordAxis - targetAxis).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  void _stopManualScroll() {
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _scrollingBackward = false;
    if (mounted) _setTeleprompterState(() => _manualScrolling = false);
  }

  void _cancelSmoothScroll() {
    _smoothScrollTimer?.cancel();
    _smoothScrollActive = false;
  }

  void _notePresenterUserScrollSignal() {
    _lastPresenterUserScrollSignalAt = DateTime.now();
  }

  bool _recentPresenterUserScrollSignal() {
    final signalAt = _lastPresenterUserScrollSignalAt;
    return signalAt != null &&
        DateTime.now().difference(signalAt) < const Duration(milliseconds: 420);
  }

  void _suppressPresenterProgrammaticPositionCommit({
    required bool immediate,
  }) {
    _presenterProgrammaticCommitBlockedUntil = DateTime.now().add(
      Duration(milliseconds: immediate ? 380 : 220),
    );
  }

  bool _presenterProgrammaticPositionCommitActive() {
    final until = _presenterProgrammaticCommitBlockedUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _presenterProgrammaticCommitBlockedUntil = null;
    return false;
  }

  void _scheduleVisibleWordWindowSync({bool force = false}) {
    if (_visibleWindowSyncScheduled) return;
    _visibleWindowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleWindowSyncScheduled = false;
      if (mounted) _syncVisibleWordWindow(force: force);
    });
  }

  void _syncVisibleWordWindow({bool force = false}) {
    final now = DateTime.now();
    final previous = _lastVisibleWindowSync;
    if (!force &&
        previous != null &&
        now.difference(previous).inMilliseconds < 150) {
      return;
    }
    _lastVisibleWindowSync = now;

    final script = ref.read(scriptProvider);
    if (script == null ||
        script.words.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final viewport = Offset.zero & MediaQuery.sizeOf(context);
    int? firstVisible;
    int? lastVisible;

    for (var i = 0; i < _wordKeys.length && i < script.words.length; i++) {
      final word = script.words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final bounds = _presenterGlobalRect(box);
      if (!bounds.overlaps(viewport)) continue;
      firstVisible ??= i;
      lastVisible = i;
    }

    ref
        .read(teleprompterProvider.notifier)
        .setVisibleWordWindow(firstVisible, lastVisible);
  }

  void _preserveReadingPositionAfterLayoutChange(double _) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final sttState = ref.read(teleprompterProvider);
    final settings = ref.read(settingsProvider);
    final speechActive = sttState.isListening || sttState.isStarting;
    final baseIndex = settings.scrollMode == 'manual' && !speechActive
        ? _manualWordIndex
        : sttState.confirmedWordIndex;
    final targetIndex = baseIndex.clamp(0, script.words.length - 1).toInt();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollToWordIndex(targetIndex, immediate: true);
      _syncVisibleWordWindow(force: true);
    });
  }

  void _resetManual() {
    _stopManualScroll();
    _manualWordIndex = 0;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  // -- Speech-mode scroll ------------------------------------------------------

  void _scrollToWordIndex(int index,
      {bool anticipate = false, bool immediate = false}) {
    final targetIndex = index;
    if (targetIndex < 0 || targetIndex >= _wordKeys.length) return;
    final key = _wordKeys[targetIndex];
    final ctx = key.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final axis = _presenterScrollAxis();
    final wordAxis = _presenterBoxAxisLeading(box, axis);
    final targetAxis = _presenterReadingTargetAxis(axis);
    final rowProgress = anticipate ? _visualRowProgress(targetIndex, box) : 0.0;
    final lineAdvance =
        (box.size.height * settings.lineSpacing).clamp(0.0, screenH * 0.22);
    final rawTarget = _scrollController.offset +
        (wordAxis - targetAxis) * axis.direction +
        rowProgress * lineAdvance;
    _scrollTarget =
        rawTarget.clamp(0.0, _scrollController.position.maxScrollExtent);
    _suppressPresenterProgrammaticPositionCommit(immediate: immediate);

    if (immediate) {
      _cancelSmoothScroll();
      _scrollController.jumpTo(_scrollTarget);
      _syncVisibleWordWindow(force: true);
      return;
    }

    // Start the smooth scroll timer if not already running
    if (!_smoothScrollActive) {
      _smoothScrollActive = true;
      _smoothScrollTimer?.cancel();
      _smoothScrollTimer =
          Timer.periodic(const Duration(milliseconds: 16), _smoothScrollTick);
    }
  }

  void _jumpToWordIndex(int index, {bool immediate = false}) {
    final script = ref.read(scriptProvider);
    if (script == null) return;
    _stopManualScroll();
    _setTeleprompterState(() => _manualWordIndex = index);
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(index, script: script);
    _scrollToWordIndex(index, immediate: immediate);
    _showControls();
  }

  double _visualRowProgress(int index, RenderBox currentBox) {
    if (index < 0 || index >= _wordKeys.length) return 0.0;
    final axis = _presenterScrollAxis();
    final currentAxis = _presenterBoxAxisCenter(currentBox, axis);
    final tolerance = (currentBox.size.height * 0.7).clamp(10.0, 90.0);

    var rowStart = index;
    for (var i = index - 1; i >= 0; i--) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      final boxAxis = _presenterBoxAxisCenter(box, axis);
      if ((boxAxis - currentAxis).abs() > tolerance) break;
      rowStart = i;
    }

    var rowEnd = index;
    for (var i = index + 1; i < _wordKeys.length; i++) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      final boxAxis = _presenterBoxAxisCenter(box, axis);
      if ((boxAxis - currentAxis).abs() > tolerance) break;
      rowEnd = i;
    }

    final span = rowEnd - rowStart;
    if (span <= 0) return 0.0;
    return ((index - rowStart) / span).clamp(0.0, 1.0).toDouble();
  }

  RenderBox? _boxForWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return null;
    final ctx = _wordKeys[index].currentContext;
    if (ctx == null) return null;
    return ctx.findRenderObject() as RenderBox?;
  }

  bool _handleStoppedBrowsingScroll(ScrollNotification notification) {
    final sttState = ref.read(teleprompterProvider);
    final settings = ref.read(settingsProvider);
    final speechActive = sttState.isListening || sttState.isStarting;
    final activeManualOverride =
        PresenterInputLockService.allowActiveManualScroll(
      settingEnabled: settings.allowScrollDuringActiveSession,
      isListening: sttState.isListening,
      isStarting: sttState.isStarting,
    );
    if (sttState.isStarting ||
        (sttState.isListening && !activeManualOverride)) {
      _userBrowsingWhileStopped = false;
      return false;
    }

    final isUserScrollStart = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final isUserScrollUpdate = notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    final userScrollIntent =
        isUserScrollStart || _recentPresenterUserScrollSignal();
    if (speechActive &&
        _presenterProgrammaticPositionCommitActive() &&
        !userScrollIntent) {
      _syncVisibleWordWindow();
      return false;
    }
    final isScrollPositionUpdate =
        notification is ScrollUpdateNotification && _userBrowsingWhileStopped;
    if (isUserScrollStart || isUserScrollUpdate) {
      _userBrowsingWhileStopped = true;
      _cancelSmoothScroll();
      _stopManualScroll();
      if (speechActive && activeManualOverride) {
        _activeManualCorrection = true;
      }
    }

    if (_userBrowsingWhileStopped &&
        (isUserScrollStart || isUserScrollUpdate || isScrollPositionUpdate)) {
      _syncVisibleWordWindow(force: true);
      if (speechActive && activeManualOverride) {
        _scheduleActiveManualCorrectionCommit();
      } else {
        _syncResumePointToReadingLine(throttled: true);
      }
    }

    if (notification is ScrollEndNotification && _userBrowsingWhileStopped) {
      _userBrowsingWhileStopped = false;
      _lastBrowsingWordSync = null;
      _syncVisibleWordWindow(force: true);
      if (speechActive && activeManualOverride) {
        _finishActiveManualCorrection();
      } else {
        _syncResumePointToReadingLine();
      }
    }
    return false;
  }

  void _scheduleActiveManualCorrectionCommit() {
    _activeManualCorrectionTimer?.cancel();
    _activeManualCorrectionTimer =
        Timer(const Duration(milliseconds: 420), _finishActiveManualCorrection);
  }

  void _finishActiveManualCorrection() {
    _activeManualCorrectionTimer?.cancel();
    _activeManualCorrectionTimer = null;
    if (!_activeManualCorrection) return;
    _activeManualCorrection = false;
    _userBrowsingWhileStopped = false;
    _lastBrowsingWordSync = null;
    _syncVisibleWordWindow(force: true);
    _syncResumePointToReadingLine();
  }

  void _syncResumePointToReadingLine({bool throttled = false}) {
    if (throttled) {
      final now = DateTime.now();
      final previous = _lastBrowsingWordSync;
      if (previous != null && now.difference(previous).inMilliseconds < 80) {
        return;
      }
      _lastBrowsingWordSync = now;
    }

    final script = ref.read(scriptProvider);
    if (script == null) return;
    if (_scrollController.hasClients && _scrollController.offset <= 1.0) {
      _setTeleprompterState(() => _manualWordIndex = 0);
      ref.read(teleprompterProvider.notifier).jumpToPosition(0, script: script);
      return;
    }
    final targetIndex = _wordIndexNearestReadingLine();
    if (targetIndex == null) return;
    _setTeleprompterState(() => _manualWordIndex = targetIndex);
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(targetIndex, script: script);
  }

  double _presenterReadingTargetAxis(_PresenterScrollAxis axis) {
    final settings = ref.read(settingsProvider);
    final lineAxis = _presenterReadingLineAxis(axis);
    final fontSize = settings.fontSize * 2.0;
    final gap = (fontSize * 0.10).clamp(4.0, 14.0);
    return lineAxis + axis.direction * gap;
  }
}
