part of 'teleprompter_provider.dart';

extension TeleprompterHeartbeat on TeleprompterNotifier {
  void _startSessionHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || _sessionStopped) return;
      _handleSessionHeartbeat();
    });
  }

  void _handleSessionHeartbeat() {
    final settings = ref.read(settingsProvider);
    final serviceListening =
        _useWhisper ? _whisperService.isListening : _sttService.isListening;
    final listening = SttRecognitionPolicyService.heartbeatListeningState(
      serviceListening: serviceListening,
      browserServiceActive: !_useWhisper && _sttService == _browserSttService,
      browserHostReadinessComplete: _sttHostReadiness?.isReady ?? false,
      browserHostTransitionInFlight: _sttHostTransitionInFlight,
    );

    if (settings.debugMode) {
      final engineName =
          _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
      final debugState = '$engineName:${listening ? "ready" : "idle"}';
      if (_lastHeartbeatDebugState != debugState) {
        _lastHeartbeatDebugState = debugState;
        _addDebugLog(
          'ENGINE HEALTH: $engineName ${listening ? "READY (speech not implied)" : "IDLE"}',
        );
      }
    } else {
      _lastHeartbeatDebugState = null;
    }

    _maybeRecoverBrowserStt(listening);
    _syncHeartbeatLocale(listening);
  }

  void _maybeRecoverBrowserStt(bool listening) {
    if (_useWhisper ||
        _sttService != _browserSttService ||
        _sttHostTransitionInFlight ||
        _sttHostReadiness?.isReady != true ||
        !listening) {
      return;
    }

    final reason = SttRecognitionPolicyService.browserRecoveryReason(
      now: DateTime.now(),
      sessionStart: _browserHostStartedAt ?? _sessionStartTime,
      lastHeartbeat: _lastBrowserHeartbeatAt,
      lastRecoverableError: _lastRecoverableSttErrorAt,
      recoverableErrorCount: _recoverableSttErrorCount,
    );
    if (reason == null) return;

    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'browser-health-degraded',
        // Missing heartbeats can be caused by transient transport/service
        // failures. Persistent quarantine is reserved for deterministic
        // embedded initialization or API incompatibility failures.
        quarantineRuntime: false,
      ),
    );
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
