part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSessionWatchdog on TeleprompterNotifier {
  void _startSessionWatchdog({
    required Script script,
    required AppSettings settings,
    required int token,
  }) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_disposed || _sessionStopped || token != _sessionToken) return;

      final now = DateTime.now();
      final engineName =
          _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
      final listening =
          _useWhisper ? _whisperService.isListening : _sttService.isListening;
      final shouldBeListening = !_useWhisper &&
          (_currentState.isListening || _currentState.isStarting);
      final canRestart = _canRestartSttFromWatchdog(now);

      _logHeartbeat(
        settings: settings,
        engineName: engineName,
        listening: listening,
        script: script,
      );

      if (SttRecognitionPolicyService.shouldRestartDroppedListener(
        shouldBeListening: shouldBeListening,
        listening: listening,
        startingSession: _startingSession,
        canRestart: canRestart,
      )) {
        _restartDroppedSttListener(now, engineName: engineName, token: token);
      }

      final appleRestartReason = _appleWatchdogRestartReason(
        now: now,
        shouldBeListening: shouldBeListening,
        listening: listening,
        canRestart: canRestart,
      );
      if (appleRestartReason != null) {
        _restartAppleSilentListener(
          now,
          engineName: engineName,
          token: token,
          reason: appleRestartReason,
        );
      }

      _warnForSilentNonAppleListener(
        settings: settings,
        listening: listening,
      );

      if (!_useWhisper && listening && _currentScript != null) {
        _syncLocaleForPosition(
          _currentScript!,
          _currentState.confirmedWordIndex + 1,
          reason: 'heartbeat',
        );
      }
    });
  }

  bool _canRestartSttFromWatchdog(DateTime now) {
    return _lastSttWatchdogRestartAt == null ||
        now.difference(_lastSttWatchdogRestartAt!) > const Duration(seconds: 8);
  }

  void _logHeartbeat({
    required AppSettings settings,
    required String engineName,
    required bool listening,
    required Script script,
  }) {
    if (!settings.debugMode) return;
    final pos = _currentState.confirmedWordIndex;
    final total = script.words.where((w) => !w.isNewline).length;
    _addDebugLog(
      'HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount',
    );
  }

  void _restartDroppedSttListener(
    DateTime now, {
    required String engineName,
    required int token,
  }) {
    _lastSttWatchdogRestartAt = now;
    _addDebugLog('[$engineName] WATCHDOG: listener dropped; restarting.');
    unawaited(_restartSttFromWatchdog(
      token: token,
      source: '[$engineName] WATCHDOG RESTART FAILED',
    ));
  }

  String? _appleWatchdogRestartReason({
    required DateTime now,
    required bool shouldBeListening,
    required bool listening,
    required bool canRestart,
  }) {
    if (_useWhisper || _sttService.platformName != 'Apple') return null;
    return SttRecognitionPolicyService.appleWatchdogRestartReason(
      now: now,
      shouldBeListening: shouldBeListening,
      listening: listening,
      startingSession: _startingSession,
      canRestart: canRestart,
      sessionStart: _sessionStartTime,
      lastNativeCallback: _lastVolLog,
    );
  }

  void _restartAppleSilentListener(
    DateTime now, {
    required String engineName,
    required int token,
    required String reason,
  }) {
    _lastSttWatchdogRestartAt = now;
    _lastVolLog = now;
    _lastSttResultAt = now;
    _addDebugLog(
      '[$engineName] WATCHDOG: $reason; restarting listener.',
    );
    unawaited(_restartSttFromWatchdog(
      token: token,
      source: '[$engineName] SILENT RESTART FAILED',
    ));
  }

  Future<void> _restartSttFromWatchdog({
    required int token,
    required String source,
  }) async {
    try {
      final result = await _sttService.restart(localeId: _activeLocale).timeout(
            const Duration(seconds: 8),
            onTimeout: () => SpeechStartResult(
              success: false,
              message:
                  'Speech recognition listener restart timed out. Try stopping and starting STT again.',
            ),
          );
      if (_disposed || _sessionStopped || token != _sessionToken) return;
      if (result.success && _sttService.requiresImmediateListeningFlag) {
        _startingSession = true;
        final now = DateTime.now();
        _lastVolLog = now;
        _lastSttResultAt = now;
        _safeSetState(
          (s) => s.copyWith(isListening: true, isStarting: false),
        );
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (token == _sessionToken) _startingSession = false;
        });
        return;
      }
      if (!result.success) {
        _safeSetState((s) => s.copyWith(
              statusMessage: result.message ?? 'Speech recognition stopped',
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
      }
    } catch (error) {
      _addDebugLog('$source: $error');
    }
  }

  void _warnForSilentNonAppleListener({
    required AppSettings settings,
    required bool listening,
  }) {
    if (!settings.debugMode ||
        _useWhisper ||
        _sttService.platformName == 'Apple' ||
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
      'SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.',
    );
    _addDebugLog(
      'FIX: Check macOS Privacy & Security -> Microphone and Speech Recognition permissions for AutoTeleprompter.',
    );
    _safeSetState((s) => s.copyWith(
          statusMessage:
              'Microphone signal weak or blocked.\n1. Check macOS Privacy & Security -> Microphone.\n2. Check Speech Recognition permission for AutoTeleprompter.',
          hasError: true,
        ));
  }
}
