part of 'script_editor_screen.dart';

extension _ScriptEditorRecentPersistenceParts on _ScriptEditorScreenState {
  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _persistRecentSafely('autosaveTimer');
    });
  }

  void _scheduleRecentUpdate({Duration delay = const Duration(seconds: 30)}) {
    _recentTimer?.cancel();
    _recentTimer = Timer(delay, () {
      if (mounted) _persistRecentSafely('scheduledRecentUpdate');
    });
  }

  void _persistRecentSafely(String source) {
    unawaited(
      _forceRecentUpdate().catchError((Object error, StackTrace stack) {
        LightweightDiagnostics.instance.recordError(
          error,
          stack,
          source: 'scriptEditor.$source',
        );
      }),
    );
  }

  Future<void> _forceRecentUpdate() async {
    _recentTimer?.cancel();
    if (_recentPersistRunning) {
      _recentPersistQueued = true;
      return;
    }
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    if (text.trim().isEmpty && _currentSessionId == null) return;
    final settings = ref.read(settingsProvider);
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    final fingerprint = _recentPersistenceFingerprint(
      text: text,
      historyJson: historyJson,
      settings: settings,
    );
    if (fingerprint == _lastRecentPersistFingerprint) return;
    _recentPersistRunning = true;
    try {
      await ref.read(settingsProvider.notifier).saveScript(
            text,
            title: _currentTitle,
            type: _sourceType,
            sourcePath: _currentSourcePath,
            historyIndex: _historyIndex,
            sessionId: _currentSessionId,
            fontSize: settings.fontSize,
            fontFamily: settings.fontFamily,
            lineSpacing: settings.lineSpacing,
            letterSpacing: settings.letterSpacing,
            wordSpacing: settings.wordSpacing,
            textAlign: settings.textAlign,
            scriptBgColor: settings.scriptBgColor,
            currentWordColor: settings.currentWordColor,
            futureWordColor: settings.futureWordColor,
            historyJson: historyJson,
          );
      _lastRecentPersistFingerprint = fingerprint;
      // Keep scriptProvider.state in sync so that a new ScriptEditorScreen
      // (created on re-entry after navigating away) reads the correct
      // historyIndex and historyJson rather than stale startup values.
      if (mounted) {
        ref.read(scriptProvider.notifier).updateHistory(
              _historyIndex,
              historyJson,
            );
      }
    } finally {
      _recentPersistRunning = false;
      if (_recentPersistQueued && mounted) {
        _recentPersistQueued = false;
        _scheduleRecentUpdate(delay: const Duration(seconds: 30));
      }
    }
  }

  void _rememberCurrentRecentFingerprint() {
    if (_controllers.isEmpty) return;
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    _lastRecentPersistFingerprint = _recentPersistenceFingerprint(
      text: text,
      historyJson: historyJson,
      settings: ref.read(settingsProvider),
    );
  }

  String _recentPersistenceFingerprint({
    required String text,
    required String historyJson,
    required AppSettings settings,
  }) {
    return [
      _currentTitle,
      _sourceType,
      _currentSessionId ?? '',
      _currentSourcePath ?? '',
      _historyIndex.toString(),
      text.length.toString(),
      text.hashCode.toString(),
      historyJson.length.toString(),
      historyJson.hashCode.toString(),
      settings.fontSize.toStringAsFixed(3),
      settings.fontFamily,
      settings.lineSpacing.toStringAsFixed(3),
      settings.letterSpacing.toStringAsFixed(3),
      settings.wordSpacing.toStringAsFixed(3),
      settings.textAlign,
      settings.scriptBgColor.toString(),
      settings.currentWordColor.toString(),
      settings.futureWordColor.toString(),
    ].join('|');
  }

  void _clearAppSelectionAfterTextInput(MarkupController editedController) {
    _overlayKey.currentState?.clearSelection();
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      if (!identical(c, editedController) &&
          c.selection.isValid &&
          !c.selection.isCollapsed) {
        final collapseAt = c.selection.extentOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
      c.refresh();
    }
    _lastFocusedController = editedController;
  }

  void _syncEditorControllersFromPresentedScript() {
    final active = ref.read(scriptProvider);
    if (active == null || active.sessionId != _currentSessionId) return;
    final currentEditorRaw = _getRefinedFullTextWithoutBookmarkSigns();
    if (active.rawText == currentEditorRaw) return;
    final blocks = active.rawText.split('\n');
    if (blocks.length != _controllers.length) return;
    _isCommandExecuting = true;
    try {
      for (var i = 0; i < blocks.length; i++) {
        final next = blocks[i];
        if (_controllers[i].text == next) continue;
        final safeOffset = _controllers[i]
            .selection
            .baseOffset
            .clamp(0, next.length);
        _controllers[i].value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: safeOffset),
        );
        _controllers[i].refresh();
      }
    } finally {
      _isCommandExecuting = false;
    }
  }
}

class _EnterSelectionRange {
  final int blockIndex;
  final TextSelection selection;
  const _EnterSelectionRange(this.blockIndex, this.selection);
}
