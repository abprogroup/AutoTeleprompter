part of 'teleprompter_screen.dart';

extension _TeleprompterManualScrollParts on _TeleprompterScreenState {
  void _startManualScroll({bool backward = false}) {
    if (!_scrollController.hasClients) return;
    _scrollingBackward = backward;
    setState(() => _manualScrolling = true);
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

      // pixels per tick: speed(wpm) × 3px × 16ms/1000ms
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
      setState(() => _manualWordIndex = bestIndex);
    }
  }

  void _stopManualScroll() {
    _manualScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
    _scrollingBackward = false;
    if (mounted) setState(() => _manualScrolling = false);
  }

  /// Item 3: compute and push the rendered visible word range to the
  /// teleprompter provider so the aligner can use it as the upper bound for
  /// opt-in visible-skip jumps. Skips newlines and unspeakable display tokens.
  /// Throttled to ~150 ms unless `force` is true.
  void _syncVisibleWordWindow({bool force = false}) {
    if (!mounted || !_scrollController.hasClients) return;
    final now = DateTime.now();
    final previous = _lastVisibleWindowSync;
    if (!force &&
        previous != null &&
        now.difference(previous).inMilliseconds < 150) {
      return;
    }
    _lastVisibleWindowSync = now;

    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;

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

  void _scheduleVisibleWordWindowSync() {
    if (_visibleWindowSyncScheduled) return;
    _visibleWindowSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleWindowSyncScheduled = false;
      if (mounted) _syncVisibleWordWindow(force: true);
    });
  }

  void _resetManual() {
    _stopManualScroll();
    _manualWordIndex = 0;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

// ── Speech-mode scroll ──────────────────────────────────────────────────────

  void _scrollToWordIndex(int index) {
    if (index < 0 || index >= _wordKeys.length) return;
    final key = _wordKeys[index];
    final ctx = key.currentContext;
    if (ctx == null) return;

    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;

    final settings = ref.read(settingsProvider);
    final screenH = MediaQuery.of(context).size.height;
    final targetY = screenH * settings.scrollLead;

    final wordPos =
        box.localToGlobal(Offset.zero, ancestor: context.findRenderObject());
    // Item 4: row-progress follow. Add a fractional advance based on how far
    // through its row the focused word is, so the scroll glide stays smooth
    // and continuous instead of snapping at row ends.
    final rowProgress = _visualRowProgress(index, box);
    final lineAdvance =
        (box.size.height * settings.lineSpacing).clamp(0.0, screenH * 0.22);
    final rawTarget = _scrollController.offset +
        wordPos.dy -
        targetY +
        rowProgress * lineAdvance;
    _scrollTarget =
        rawTarget.clamp(0.0, _scrollController.position.maxScrollExtent);

    // Start the smooth scroll timer if not already running
    if (!_smoothScrollActive) {
      _smoothScrollActive = true;
      _smoothScrollTimer?.cancel();
      _smoothScrollTimer =
          Timer.periodic(const Duration(milliseconds: 16), _smoothScrollTick);
    }
  }

  /// Item 4: how far through its current row the focused word is (0.0 .. 1.0).
  /// Walks neighbours by Y-tolerance to find row start and end, returns the
  /// position of `index` within that row.
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

  /// Item 4 (scroll lock) + Item 5 (stopped browsing/resume-point sync).
  /// While STT is listening or starting, drop user drag-scroll attempts so
  /// the active reading position stays on screen. While STT is stopped, the
  /// user may drag freely; on scroll-end we snap the resume point to the
  /// reading line so the next mic start picks up there.
  bool _handleStoppedBrowsingScroll(ScrollNotification notification) {
    final sttState = ref.read(teleprompterProvider);
    if (sttState.isListening || sttState.isStarting) {
      _userBrowsingWhileStopped = false;
      return false;
    }
    final isUserScrollStart = notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final isUserScrollUpdate = notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle;
    if (isUserScrollStart || isUserScrollUpdate) {
      _userBrowsingWhileStopped = true;
      _smoothScrollTimer?.cancel();
      _smoothScrollActive = false;
      _stopManualScroll();
    }
    if (notification is ScrollEndNotification && _userBrowsingWhileStopped) {
      _userBrowsingWhileStopped = false;
      _syncVisibleWordWindow(force: true);
      _syncResumePointToReadingLine();
    }
    return false;
  }

  /// Item 5: pick the word nearest the reading line and store it as the
  /// resume point so the next `startSession()` continues from there.
  void _syncResumePointToReadingLine() {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty || !_scrollController.hasClients) {
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
    setState(() => _manualWordIndex = targetIndex);
    ref
        .read(teleprompterProvider.notifier)
        .jumpToPosition(targetIndex, script: script);
  }

  /// 60fps smooth scroll — glides toward _scrollTarget using lerp.
  /// Stops automatically when close enough.
  void _smoothScrollTick(Timer timer) {
    if (!mounted || !_scrollController.hasClients) {
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }

    final current = _scrollController.offset;
    final diff = _scrollTarget - current;

    // Close enough — snap and stop
    if (diff.abs() < 0.5) {
      _scrollController.jumpTo(_scrollTarget);
      timer.cancel();
      _smoothScrollActive = false;
      return;
    }

    // Lerp factor: 0.12 gives smooth ~8-frame glide.
    // Larger = snappier, smaller = silkier.
    final next = current + diff * 0.12;
    _scrollController
        .jumpTo(next.clamp(0.0, _scrollController.position.maxScrollExtent));
  }

  void _showSettings() {
    _showControls();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => const TeleprompterSettingsPanel(),
    );
  }
}
