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

    _maybeRecoverBrowserStt(script, listening);
    _syncHeartbeatLocale(listening);
  }

  void _maybeRecoverBrowserStt(Script script, bool listening) {
    if (_useWhisper ||
        _sttService != _browserSttService ||
        !listening ||
        _sttRecoveryInFlight) {
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

    _recoverableSttErrorCount = 0;
    _lastRecoverableSttErrorAt = null;
    unawaited(_recoverBrowserStt(script, reason: reason));
  }

  Future<void> _recoverBrowserStt(
    Script script, {
    required String reason,
  }) async {
    if (_sttRecoveryInFlight || _disposed || _sessionStopped) return;
    final token = _sessionToken;
    _sttRecoveryInFlight = true;
    _addDebugLog('[Browser Online STT] RECOVERY: $reason');
    LightweightDiagnostics.instance.record(
      'stt',
      'browser STT recovery',
      data: {'reason': reason, 'position': _currentState.confirmedWordIndex},
    );

    try {
      final settings = ref.read(settingsProvider);
      final locale = _activeLocale ??
          _scriptLanguageLocale ??
          TeleprompterNotifier.resolveInitialSttLocale(
            script.words,
            startIndex: _currentState.confirmedWordIndex,
            sectionLocales: _sectionLocales,
          );
      final selectedMicId = settings.sttInputDeviceId.trim();
      final selectedMicLabel = settings.sttInputDeviceLabel.trim();

      _safeSetState((s) => s.copyWith(
            isStarting: true,
            statusMessage: '',
            hasError: false,
          ));
      await _browserSttService.stop();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (_disposed || _sessionStopped || token != _sessionToken) return;

      _browserSttService.setAudioInputDevice(
        selectedMicId.isEmpty ? null : selectedMicId,
        label: selectedMicLabel.isEmpty
            ? 'System default microphone'
            : selectedMicLabel,
      );
      final result = await _browserSttService.start(localeId: locale);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _browserSttService.stop();
        return;
      }
      if (!result.success) {
        _safeSetState((s) => s.copyWith(
              isListening: false,
              isStarting: false,
              hasError: true,
              statusMessage: result.message ?? 'Speech recognition failed',
            ));
        return;
      }

      _lastBrowserHeartbeatAt = DateTime.now();
      final webViewUrl = _browserSttService.sttWebViewUrl;
      _safeSetState((s) => s.copyWith(
            sttWebViewUrl: webViewUrl,
            isStarting: true,
            hasError: false,
            statusMessage: '',
          ));
    } finally {
      _sttRecoveryInFlight = false;
    }
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
