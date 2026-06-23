part of 'script_editor_screen.dart';

extension _ScriptEditorRecentPersistenceParts on _ScriptEditorScreenState {
  void _startAutoSave() {
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final text = _getRefinedFullTextWithoutBookmarkSigns();
      if (text.isEmpty && _currentTitle == 'New Project') return;
      if (_sourceType == _walkthroughTempSourceType) return;
      _persistRecentSafely('autosaveTimer');
    });
  }

  void _scheduleRecentUpdate({
    Duration delay = const Duration(seconds: 30),
  }) {
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
    if (_sourceType == _walkthroughTempSourceType) return;
    if (_recentPersistRunning) {
      _recentPersistQueued = true;
      return;
    }
    final text = _getRefinedFullTextWithoutBookmarkSigns();
    if (text.trim().isEmpty) return;
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
}
