part of 'content_creator_screen.dart';

extension _ContentCreatorScrollState on _ContentCreatorScreenState {
  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _wordTrackTimer?.cancel();
  }

  void _handleContentScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_contentRotationRecenterActive()) return;
    final sttState = ref.read(teleprompterProvider);
    final settings = ref.read(settingsProvider);
    final allowActiveManualScroll =
        PresenterInputLockService.allowActiveManualScroll(
      settingEnabled: settings.allowScrollDuringActiveSession,
      isListening: sttState.isListening,
      isStarting: sttState.isStarting,
    );
    if (PresenterInputLockService.inputLocked(
      isWindows: Platform.isWindows,
      isListening: sttState.isListening,
      isStarting: sttState.isStarting,
      allowActiveManualScroll: allowActiveManualScroll,
    )) {
      return;
    }
    _updateActiveWordFromScroll(commitProvider: true);
  }

  void _updateActiveWordFromScroll({bool commitProvider = false}) {
    final script = ref.read(scriptProvider);
    if (!mounted ||
        script == null ||
        script.words.isEmpty ||
        !_scrollController.hasClients ||
        _wordKeys.isEmpty) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final targetLine = _contentReadingLineCoordinate(settings, screenSize);
    final wordLimit = script.words.length.clamp(0, _wordKeys.length).toInt();
    if (_scrollController.offset <= 1.0) {
      if (_activeWordIndex != 0) {
        _updateContentCreatorState(() => _activeWordIndex = 0);
      }
      if (commitProvider) _scheduleContentPositionCommit(0);
      return;
    }

    var bestIndex = _activeWordIndex;
    var bestDistance = double.infinity;
    for (var i = 0; i < wordLimit; i++) {
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final distance = _contentUsesVerticalReadingLine(settings)
          ? (center.dx - targetLine).abs()
          : (center.dy - targetLine).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex != _activeWordIndex) {
      _updateContentCreatorState(() => _activeWordIndex = bestIndex);
      if (commitProvider) _scheduleContentPositionCommit(bestIndex);
    } else if (commitProvider) {
      _scheduleContentPositionCommit(bestIndex);
    }
    _syncContentVisibleWordWindow();
  }

  bool _contentRotationRecenterActive() {
    final until = _contentRotationRecenterUntil;
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _contentRotationRecenterUntil = null;
    return false;
  }

  int _contentQuarterTurns(AppSettings settings) {
    return ((settings.flipRotation ~/ 90) % 4 + 4) % 4;
  }

  bool _contentUsesVerticalReadingLine(AppSettings settings) {
    return _contentQuarterTurns(settings).isOdd;
  }

  double _contentReadingLineCoordinate(AppSettings settings, Size size) {
    final lead = settings.scrollLead.clamp(0.0, 1.0).toDouble();
    final turns = _contentQuarterTurns(settings);
    if (turns == 1) return size.width * (1.0 - lead);
    if (turns == 3) return size.width * lead;
    return size.height * lead;
  }

  void _syncContentVisibleWordWindow() {
    final script = ref.read(scriptProvider);
    if (!mounted || script == null || script.words.isEmpty) return;
    final settings = ref.read(settingsProvider);
    final size = MediaQuery.sizeOf(context);
    final verticalLine = _contentUsesVerticalReadingLine(settings);
    final minCoord = verticalLine ? 0.0 : 0.0;
    final maxCoord = verticalLine ? size.width : size.height;
    int? first;
    int? last;
    final wordLimit = script.words.length.clamp(0, _wordKeys.length).toInt();
    for (var i = 0; i < wordLimit; i++) {
      final word = script.words[i];
      if (word.isNewline) continue;
      final ctx = _wordKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      final start = verticalLine
          ? (topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx)
          : (topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy);
      final end = verticalLine
          ? (topLeft.dx > bottomRight.dx ? topLeft.dx : bottomRight.dx)
          : (topLeft.dy > bottomRight.dy ? topLeft.dy : bottomRight.dy);
      if (end < minCoord || start > maxCoord) continue;
      first ??= i;
      last = i;
    }
    ref.read(teleprompterProvider.notifier).setVisibleWordWindow(first, last);
  }

  void _scheduleContentPositionCommit(int index) {
    final script = ref.read(scriptProvider);
    if (script == null || script.words.isEmpty) return;
    final target = index.clamp(0, script.words.length - 1).toInt();
    if (_pendingPositionCommit == target &&
        _positionCommitTimer?.isActive == true) {
      return;
    }
    _pendingPositionCommit = target;
    _positionCommitTimer?.cancel();
    _positionCommitTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      final activeScript = ref.read(scriptProvider);
      final pending = _pendingPositionCommit;
      _pendingPositionCommit = null;
      if (activeScript == null ||
          activeScript.words.isEmpty ||
          pending == null) {
        return;
      }
      final clamped = pending.clamp(0, activeScript.words.length - 1).toInt();
      final current = ref.read(teleprompterProvider).confirmedWordIndex;
      if (current == clamped) return;
      ref.read(teleprompterProvider.notifier).jumpToPosition(
            clamped,
            script: activeScript,
          );
    });
  }

  String _formatTimer(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return "$h:${m.toString().padLeft(2, '0')}:"
          "${s.toString().padLeft(2, '0')}";
    }
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }
}
