part of 'teleprompter_provider.dart';

extension TeleprompterNotifierAppleQuality on TeleprompterNotifier {
  void _resetAppleRecognitionQuality({bool clearMessage = true}) {
    _poorAppleRecognitionStartedAt = null;
    _lastLoggedAppleHealth = null;
    _lastLoggedAppleAction = null;
    _appleRetryBurstWindowStart = null;
    _appleRetryBurstCount = 0;
    if (_disposed) return;
    _safeSetState((s) => s.copyWith(
          sttHealth: AppleSttHealth.healthy.name,
          sttRecognitionQuality: 1.0,
          sttQualityMessage: clearMessage ? '' : s.sttQualityMessage,
          statusMessage: clearMessage && !s.hasError ? '' : s.statusMessage,
        ));
  }

  void _recordAppleRetryError() {
    final now = DateTime.now();
    final windowStart = _appleRetryBurstWindowStart;
    if (windowStart == null ||
        now.difference(windowStart) > const Duration(seconds: 12)) {
      _appleRetryBurstWindowStart = now;
      _appleRetryBurstCount = 1;
    } else {
      _appleRetryBurstCount++;
    }
    _addDebugLog('[APPLE] retry error burst=$_appleRetryBurstCount');
  }

  void _applyAppleQualityAssessment(
    AppleSttHealthAssessment assessment, {
    String heard = '',
    int? repeatCount,
    int? waitCount,
  }) {
    final healthChanged = _lastLoggedAppleHealth != assessment.health ||
        _lastLoggedAppleAction != assessment.action;
    if (healthChanged) {
      _lastLoggedAppleHealth = assessment.health;
      _lastLoggedAppleAction = assessment.action;
      final details = <String>[
        'health=${assessment.health.name}',
        'action=${assessment.action.name}',
        'quality=${(assessment.quality * 100).round()}%',
        if (waitCount != null) 'wait=$waitCount',
        if (repeatCount != null) 'repeat=$repeatCount',
        if (heard.trim().isNotEmpty)
          'heard="${TeleprompterNotifier.debugTranscriptSnippet(heard)}"',
      ].join(' | ');
      _addDebugLog('[QUALITY] $details');
    }

    var message = assessment.message;
    if (assessment.action == AppleSttRecoveryAction.suggestNoisyRoom) {
      message =
          '$message Try Noisy room mode for more patient matching and fewer restarts.';
    } else if (assessment.action ==
        AppleSttRecoveryAction.suggestManualFallback) {
      message =
          '$message Speech control will keep listening; an operator can use Manual Speed or Remote Control as a backup.';
    }

    _safeSetState((s) => s.copyWith(
          sttHealth: assessment.healthKey,
          sttQualityMessage: message,
          sttRecognitionQuality: assessment.quality,
          statusMessage: assessment.health == AppleSttHealth.engineDropped
              ? message
              : s.statusMessage,
          hasError: assessment.health == AppleSttHealth.engineDropped,
          isListening: assessment.health == AppleSttHealth.engineDropped
              ? false
              : s.isListening || !_sessionStopped,
          isStarting: assessment.health == AppleSttHealth.engineDropped
              ? true
              : s.isStarting,
        ));
  }

  bool _handlePoorAppleRecognitionIfNeeded({
    required Script script,
    required String transcript,
  }) {
    if (_useWhisper || _sttService.platformName != 'Apple') return false;
    if (_sessionStopped || _disposed) return false;

    final now = DateTime.now();
    final repeatCount = _recordNoProgressTranscript(transcript);
    _poorAppleRecognitionStartedAt ??= now;
    final poorDuration = now.difference(_poorAppleRecognitionStartedAt!);
    final settings = ref.read(settingsProvider);
    final assessment = SttRecognitionPolicyService.classifyAppleSttHealth(
      reliabilityMode: settings.sttReliabilityMode,
      shouldBeListening: _currentState.isListening || _currentState.isStarting,
      listening: _sttService.isListening,
      startingSession: _startingSession,
      canRestart: _canRestartSttFromWatchdog(now),
      now: now,
      sessionStart: _sessionStartTime,
      lastNativeCallback: _lastVolLog,
      soundLevel: _currentState.soundLevel,
      transcript: transcript,
      matchedScript: false,
      noProgressCount: _noProgressCount,
      repeatedTranscriptCount: repeatCount,
      poorQualityDuration: poorDuration,
      retryBurstCount: _appleRetryBurstCount,
      noNativeCallbacksAfter:
          TeleprompterNotifier._appleNativeCallbackStaleAfter,
    );

    if (assessment.health == AppleSttHealth.healthy) return false;
    _applyAppleQualityAssessment(
      assessment,
      heard: transcript,
      repeatCount: repeatCount,
      waitCount: _noProgressCount,
    );

    if (assessment.shouldRestart) {
      return _restartPoorAppleRecognition(
        now: now,
        assessment: assessment,
        script: script,
        transcript: transcript,
        repeatCount: repeatCount,
      );
    }

    final shouldSoftRestart =
        SttRecognitionPolicyService.shouldSoftRestartPoorAppleRecognition(
      reliabilityMode: settings.sttReliabilityMode,
      noProgressCount: _noProgressCount,
      repeatedTranscriptCount: repeatCount,
      poorQualityDuration: poorDuration,
      now: now,
      lastRestartAt: _lastPoorAppleRecognitionRestartAt,
      cooldown: TeleprompterNotifier._applePoorQualityRestartCooldown,
    );
    if (!shouldSoftRestart) return false;

    return _restartPoorAppleRecognition(
      now: now,
      assessment: const AppleSttHealthAssessment(
        health: AppleSttHealth.recognizingWrongWords,
        action: AppleSttRecoveryAction.softRestart,
        message:
            'Apple Speech is still hearing unmatched fragments. Refreshing the listener without moving the script.',
        quality: 0.32,
      ),
      script: script,
      transcript: transcript,
      repeatCount: repeatCount,
    );
  }

  bool _restartPoorAppleRecognition({
    required DateTime now,
    required AppleSttHealthAssessment assessment,
    required Script script,
    required String transcript,
    required int repeatCount,
  }) {
    final lastRecoveryAt = _lastPoorAppleRecognitionRestartAt;
    if (lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) <
            TeleprompterNotifier._applePoorQualityRestartCooldown) {
      return false;
    }

    _lastPoorAppleRecognitionRestartAt = now;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _resetSttEvidenceGate();
    _resetSequentialSttStreak();
    _resetVisibleLocaleAssist();
    _resetStaleNoProgressTracking();
    _fluidAdvanceTimer?.cancel();
    _applyAppleQualityAssessment(
      assessment,
      heard: transcript,
      repeatCount: repeatCount,
      waitCount: _noProgressCount,
    );

    final debugHeard = TeleprompterNotifier.debugTranscriptSnippet(transcript);
    _addDebugLog(
      '[RECOVERY] ${assessment.shouldFullRestart ? "full" : "soft"} Apple STT refresh | heard="$debugHeard"',
    );
    LightweightDiagnostics.instance.record(
      'stt',
      assessment.shouldFullRestart
          ? 'apple engine full restart'
          : 'apple poor recognition soft restart',
      data: {
        'heard': transcript,
        'position': _currentState.confirmedWordIndex,
        'scriptWords': script.words.length,
        'repeatCount': repeatCount,
        'health': assessment.health.name,
        'action': assessment.action.name,
      },
    );
    _lastSttWatchdogRestartAt = now;
    unawaited(_restartSttFromWatchdog(
      token: _sessionToken,
      source: '[APPLE] QUALITY RECOVERY FAILED',
      forceFullCycle: assessment.shouldFullRestart,
    ));
    return true;
  }

  void _updateAppleHealthFromHeartbeat({
    required DateTime now,
    required bool shouldBeListening,
    required bool listening,
    required bool canRestart,
  }) {
    if (_useWhisper || _sttService.platformName != 'Apple') return;
    if (_disposed || _sessionStopped || !shouldBeListening) return;

    final lastResultAt = _lastSttResultAt ?? _sessionStartTime;
    final secondsSinceUsefulResult = lastResultAt == null
        ? 0
        : now.difference(lastResultAt).inSeconds.clamp(0, 120).toInt();
    if (secondsSinceUsefulResult < 8 && _noProgressCount == 0) {
      return;
    }

    _poorAppleRecognitionStartedAt ??= now;
    final derivedNoProgress =
        (secondsSinceUsefulResult / 5).floor().clamp(0, 24).toInt();
    final assessment = SttRecognitionPolicyService.classifyAppleSttHealth(
      reliabilityMode: ref.read(settingsProvider).sttReliabilityMode,
      shouldBeListening: shouldBeListening,
      listening: listening,
      startingSession: _startingSession,
      canRestart: canRestart,
      now: now,
      sessionStart: _sessionStartTime,
      lastNativeCallback: _lastVolLog,
      soundLevel: _currentState.soundLevel,
      transcript: '',
      matchedScript: false,
      noProgressCount: _noProgressCount > derivedNoProgress
          ? _noProgressCount
          : derivedNoProgress,
      repeatedTranscriptCount: _staleNoProgressTranscriptCount,
      poorQualityDuration: now.difference(_poorAppleRecognitionStartedAt!),
      retryBurstCount: _appleRetryBurstCount,
      noNativeCallbacksAfter:
          TeleprompterNotifier._appleNativeCallbackStaleAfter,
    );

    if (assessment.health == AppleSttHealth.healthy ||
        assessment.health == AppleSttHealth.engineDropped) {
      return;
    }
    _applyAppleQualityAssessment(
      assessment,
      waitCount: _noProgressCount > derivedNoProgress
          ? _noProgressCount
          : derivedNoProgress,
    );
  }

  String _noProgressTranscriptKey(String transcript) {
    final words = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '';
    final start = words.length > 8 ? words.length - 8 : 0;
    return words.sublist(start).join(' ');
  }

  int _recordNoProgressTranscript(String transcript) {
    final key = _noProgressTranscriptKey(transcript);
    if (key.isEmpty) {
      _resetStaleNoProgressTracking();
      return 0;
    }
    if (key == _lastNoProgressTranscriptKey) {
      _staleNoProgressTranscriptCount++;
    } else {
      _lastNoProgressTranscriptKey = key;
      _staleNoProgressTranscriptCount = 1;
    }
    return _staleNoProgressTranscriptCount;
  }
}
