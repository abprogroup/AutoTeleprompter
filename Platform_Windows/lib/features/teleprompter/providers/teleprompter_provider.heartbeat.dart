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
    final serviceListening =
        _useWhisper ? _whisperService.isListening : _sttService.isListening;
    final listening = SttRecognitionPolicyService.heartbeatListeningState(
      serviceListening: serviceListening,
      browserServiceActive: !_useWhisper && _sttService == _browserSttService,
      browserHostReadinessComplete: _sttHostReadiness?.isReady ?? false,
      browserHostTransitionInFlight: _sttHostTransitionInFlight,
    );

    if (settings.debugMode) {
      final pos = _currentState.confirmedWordIndex;
      final total = script.words.where((w) => !w.isNewline).length;
      _addDebugLog(
          'HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');
      _maybeWarnAboutSilentListening(listening);
    }

    _maybeRecoverBrowserStt(listening);
    _syncHeartbeatLocale(listening);
  }

  void _maybeRecoverBrowserStt(bool listening) {
    if (_useWhisper ||
        _useExternalEdgeSttHost ||
        _sttService != _browserSttService ||
        _sttHostTransitionInFlight ||
        _sttHostReadiness?.isReady != true ||
        !listening) {
      return;
    }

    final reason = SttRecognitionPolicyService.browserRecoveryReason(
      now: DateTime.now(),
      sessionStart: _sessionStartTime,
      lastHeartbeat: _lastBrowserHeartbeatAt,
      lastRecoverableError: _lastRecoverableSttErrorAt,
      recoverableErrorCount: _recoverableSttErrorCount,
    );
    if (reason == null) return;

    unawaited(_handleBrowserHostFailure(
      reasonCode: 'browser-health-degraded',
      quarantineRuntime: true,
    ));
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
        'FIX: Check Windows Settings > Privacy & security > Microphone, and install the needed Windows speech pack if available.');
    _safeSetState((s) => s.copyWith(
          statusMessage:
              'Microphone signal weak or blocked.\n1. Check Windows Settings > Privacy & security > Microphone.\n2. Check Windows Settings > Time & Language > Speech.',
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
