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
        now: now,
        sessionStart: _sessionStartTime,
        lastNativeCallback: _lastVolLog,
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
      } else {
        _updateAppleHealthFromHeartbeat(
          now: now,
          shouldBeListening: shouldBeListening,
          listening: listening,
          canRestart: canRestart,
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
        now.difference(_lastSttWatchdogRestartAt!) >
            const Duration(seconds: 20);
  }

  void _logHeartbeat({
    required AppSettings settings,
    required String engineName,
    required bool listening,
    required Script script,
  }) {
    if (!settings.debugMode) return;
    final pos = _currentState.confirmedWordIndex;
    final lastIndex = script.words.isEmpty ? 0 : script.words.length - 1;
    _addDebugLog(
      'HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$lastIndex | stuck=$_noProgressCount',
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
      noNativeCallbacksAfter:
          TeleprompterNotifier._appleNativeCallbackStaleAfter,
    );
  }

  void _restartAppleSilentListener(
    DateTime now, {
    required String engineName,
    required int token,
    required String reason,
  }) {
    final restartCount = _recordAppleSilentRestart(now);
    final forceFullCycle =
        restartCount >= TeleprompterNotifier._appleSilentRestartLimit;
    _lastSttWatchdogRestartAt = now;
    _resetSpeechActivityMeter();
    _addDebugLog(
      '[$engineName] WATCHDOG: $reason; '
      '${forceFullCycle ? "full-resetting" : "restarting"} listener '
      '(attempt $restartCount/${TeleprompterNotifier._appleSilentRestartLimit}).',
    );

    _safeSetState((s) => s.copyWith(
          statusMessage: restartCount >=
                  TeleprompterNotifier._appleSilentRestartLimit
              ? 'Speech recognition is not returning audio callbacks. Recovering the microphone listener...'
              : 'Recovering speech recognition...',
          hasError:
              restartCount >= TeleprompterNotifier._appleSilentRestartLimit,
          isListening: true,
          isStarting: true,
          soundLevel: 0.0,
          sttHealth: AppleSttHealth.engineDropped.name,
          sttQualityMessage:
              'Apple Speech stopped returning microphone callbacks. Recovering the listener...',
          sttRecognitionQuality: 0.0,
        ));

    unawaited(_restartSttFromWatchdog(
      token: token,
      source: '[$engineName] SILENT RESTART FAILED',
      forceFullCycle: forceFullCycle,
    ));
  }

  int _recordAppleSilentRestart(DateTime now) {
    final windowStart = _appleSilentRestartWindowStart;
    if (windowStart == null ||
        now.difference(windowStart) >
            TeleprompterNotifier._appleSilentRestartWindow) {
      _appleSilentRestartWindowStart = now;
      _appleSilentRestartCount = 1;
      return _appleSilentRestartCount;
    }
    _appleSilentRestartCount++;
    return _appleSilentRestartCount;
  }

  Future<void> _restartSttFromWatchdog({
    required int token,
    required String source,
    bool forceFullCycle = false,
  }) async {
    try {
      final SpeechStartResult result;
      if (forceFullCycle) {
        await _sttService.stop().timeout(const Duration(seconds: 4));
        if (_disposed || _sessionStopped || token != _sessionToken) return;
        await Future.delayed(const Duration(milliseconds: 600));
        if (_sttService.requiresImmediateListeningFlag) {
          _startingSession = true;
          _safeSetState((s) => s.copyWith(
                isListening: true,
                isStarting: true,
                soundLevel: 0.0,
                statusMessage: 'Recovering speech recognition...',
                hasError: false,
              ));
        }
        result = await _sttService.start(localeId: _activeLocale).timeout(
              const Duration(seconds: 8),
              onTimeout: () => SpeechStartResult(
                success: false,
                message:
                    'Speech recognition full reset timed out. Try stopping and starting STT again.',
              ),
            );
      } else {
        result = await _sttService.restart(localeId: _activeLocale).timeout(
              const Duration(seconds: 8),
              onTimeout: () => SpeechStartResult(
                success: false,
                message:
                    'Speech recognition listener restart timed out. Try stopping and starting STT again.',
              ),
            );
      }
      if (_disposed || _sessionStopped || token != _sessionToken) return;
      if (result.success && _sttService.requiresImmediateListeningFlag) {
        _startingSession = true;
        _resetAppleRecognitionQuality();
        _safeSetState(
          (s) => s.copyWith(
            isListening: true,
            isStarting: false,
            soundLevel: 0.0,
          ),
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
