part of 'teleprompter_provider.dart';

extension TeleprompterHeartbeat on TeleprompterNotifier {
  void _startSessionHeartbeat(Script script) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || _sessionStopped) return;
      _handleSessionHeartbeat(script);
    });
  }

  void _handleSessionHeartbeat(Script script) {
    final settings = ref.read(settingsProvider);
    final engineName =
        _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
    final listening =
        _useWhisper ? _whisperService.isListening : _sttService.isListening;

    if (settings.debugMode) {
      final pos = _currentState.confirmedWordIndex;
      final total = script.words.where((w) => !w.isNewline).length;
      _addDebugLog(
          'HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');
      _maybeWarnAboutSilentListening(listening);
    }

    _syncHeartbeatLocale(listening);
  }

  void _maybeWarnAboutSilentListening(bool listening) {
    if (_useWhisper ||
        !listening ||
        _silentWarningFired ||
        _lastVolLog != null ||
        _sessionStartTime == null) {
      return;
    }

    final elapsed = DateTime.now().difference(_sessionStartTime!);
    if (elapsed.inSeconds < 10) return;

    _silentWarningFired = true;
    _addDebugLog(
        'SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.');
    _addDebugLog(
        'FIX: Ensure "Online Speech Recognition" is ON in Privacy Settings or install the Hebrew Offline Pack.');
    _safeSetState((s) => s.copyWith(
          statusMessage:
              'Microphone signal weak or blocked.\n1. Check Privacy Settings -> Microphone.\n2. Ensure "Online Speech Recognition" is enabled.',
          hasError: true,
        ));
  }

  void _syncHeartbeatLocale(bool listening) {
    if (_useWhisper || !listening || _currentScript == null) return;

    final policy = TeleprompterNotifier.recognitionPolicyForSettings(
      ref.read(settingsProvider),
    );
    if (policy.bulletMode && _noProgressCount > 0) return;

    _syncLocaleForPosition(
      _currentScript!,
      _currentState.confirmedWordIndex + 1,
      reason: 'heartbeat',
    );
  }
}
