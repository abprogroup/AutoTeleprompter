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
      final speed =
          settings.scrollMode == 'manual' ? settings.scrollSpeed : 100.0;
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
    final settings = ref.read(settingsProvider);
    final targetScreenY =
        MediaQuery.of(context).size.height * settings.scrollLead;

    int bestIndex = _manualWordIndex;
    double bestDist = double.infinity;

    final start = (_manualWordIndex - 3).clamp(0, _wordKeys.length - 1);
    final end = (_manualWordIndex + 15).clamp(0, _wordKeys.length - 1);

    for (int i = start; i <= end; i++) {
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final posY = box.localToGlobal(Offset.zero).dy;
      final dist = (posY - targetScreenY).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }

    if (bestIndex != _manualWordIndex) {
      _setTeleprompterState(() => _manualWordIndex = bestIndex);
    }
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

  void _scheduleVisibleWordWindowSync() {
    if (_visibleWindowSyncScheduled) return;
    _visibleWindowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleWindowSyncScheduled = false;
      if (mounted) _syncVisibleWordWindow(force: true);
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
    final viewportH = MediaQuery.of(context).size.height;
    int? firstVisible;
    int? lastVisible;

    for (var i = 0; i < _wordKeys.length && i < script.words.length; i++) {
      final word = script.words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom < 0 || top > viewportH) continue;
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
    final targetY = screenH * settings.scrollLead;

    final wordPos =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    final rowProgress = anticipate ? _visualRowProgress(targetIndex, box) : 0.0;
    final lineAdvance =
        (box.size.height * settings.lineSpacing).clamp(0.0, screenH * 0.22);
    final rawTarget = _scrollController.offset +
        wordPos.dy -
        targetY +
        rowProgress * lineAdvance;
    _scrollTarget =
        rawTarget.clamp(0.0, _scrollController.position.maxScrollExtent);

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
    final currentDy = currentBox.localToGlobal(Offset.zero).dy;
    final tolerance = (currentBox.size.height * 0.7).clamp(10.0, 90.0);

    var rowStart = index;
    for (var i = index - 1; i >= 0; i--) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      final dy = box.localToGlobal(Offset.zero).dy;
      if ((dy - currentDy).abs() > tolerance) break;
      rowStart = i;
    }

    var rowEnd = index;
    for (var i = index + 1; i < _wordKeys.length; i++) {
      final box = _boxForWordIndex(i);
      if (box == null) break;
      final dy = box.localToGlobal(Offset.zero).dy;
      if ((dy - currentDy).abs() > tolerance) break;
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
    final activeManualOverride =
        settings.allowScrollDuringActiveSession && sttState.isListening;
    if (sttState.isStarting ||
        (sttState.isListening && !activeManualOverride)) {
      _userBrowsingWhileStopped = false;
      return false;
    }

    final isUserScrollStart = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final isUserScrollUpdate = notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (isUserScrollStart || isUserScrollUpdate) {
      _userBrowsingWhileStopped = true;
      _cancelSmoothScroll();
      _stopManualScroll();
    }

    if (notification is ScrollEndNotification && _userBrowsingWhileStopped) {
      _userBrowsingWhileStopped = false;
      _syncVisibleWordWindow(force: true);
      _syncResumePointToReadingLine();
    }
    return false;
  }

  void _syncResumePointToReadingLine() {
    final script = ref.read(scriptProvider);
    if (script == null ||
        script.words.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final targetScreenY =
        MediaQuery.of(context).size.height * settings.scrollLead;

    int? bestIndex;
    double bestDist = double.infinity;
    for (var i = 0; i < _wordKeys.length && i < script.words.length; i++) {
      if (script.words[i].isNewline) continue;
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final posY = box.localToGlobal(Offset.zero).dy;
      final dist = (posY - targetScreenY).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }

    final targetIndex = bestIndex;
    if (targetIndex == null) return;
    _setTeleprompterState(() => _manualWordIndex = targetIndex);
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(targetIndex, script: script);
  }
}
