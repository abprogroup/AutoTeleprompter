part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttResult on TeleprompterNotifier {
  static const _transcriptBuffer = SttTranscriptBufferService();
  static const _movementPolicy = SttMovementPolicyService();

  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));
    if (_handleVoiceCommand(result.words)) return;

    final rawTranscript = result.words;
    if (_shouldIgnorePostAdvanceApplePartial(rawTranscript)) return;

    final buffer = _transcriptBuffer.update(
      rawTranscript: rawTranscript,
      transcriptFloor: _transcriptFloor,
      recentWordWindow: TeleprompterNotifier._sttLiveAlignmentWindowWords,
    );
    _transcriptFloor = buffer.transcriptFloor;
    if (!buffer.hasFreshSpeech) return;

    _accumulatedTranscript = buffer.recentTranscript;
    final script = _currentScript!;
    final settings = ref.read(settingsProvider);
    final policy = TeleprompterNotifier.recognitionPolicyForSettings(settings);
    final strictBulletMode = policy.bulletMode;
    final maxSkipTargetIndex = TeleprompterNotifier.resolveVisibleSkipTarget(
      visibleSkipEnabled: policy.visibleSkipEnabled,
      strictBulletMode: false,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final aligned = _bestAlignmentForTranscript(
      script: script,
      transcript: _accumulatedTranscript,
      policy: policy,
      strictBulletMode: strictBulletMode,
      maxSkipTargetIndex: maxSkipTargetIndex,
    );
    final engineTag = _useWhisper ? '[Whisper]' : '[Speech]';

    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _sttEvidenceTrackingState = SttEvidenceTrackingState.recovering;
      _addTrackDebug(
        engineTag: engineTag,
        decision: SttMovementDecision(
          action: SttMovementAction.hold,
          nextState: _sttEvidenceTrackingState,
          targetIndex: _currentState.confirmedWordIndex,
          label: 'TRACK_HOLD',
          reason: 'standby_lock',
          thresholdLabel: 'none',
          evidenceScore: 0,
          neededScore: 0,
        ),
        alignment: aligned,
        transcript: _accumulatedTranscript,
      );
      return;
    }

    if (aligned.shouldAdvance &&
        aligned.confirmedWordIndex > _currentState.confirmedWordIndex) {
      _handleMovementCandidate(
        aligned: aligned,
        script: script,
        policy: policy,
        maxSkipTargetIndex: maxSkipTargetIndex,
        transcript: _accumulatedTranscript,
        engineTag: engineTag,
      );
      return;
    }

    _handleNoMovementCandidate(
      aligned: aligned,
      script: script,
      policy: policy,
      strictBulletMode: strictBulletMode,
      transcript: _accumulatedTranscript,
      spokenWordCount: buffer.spokenWords.length,
      freshWords: buffer.freshWords,
      engineTag: engineTag,
    );
  }

  bool _handleVoiceCommand(String rawWords) {
    final words = rawWords.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);
      if (words.contains('stop prompt') ||
          words.contains('\u05E2\u05E6\u05D5\u05E8') ||
          words.contains('\u05E2\u05E6\u05D9\u05E8\u05D4')) {
        _addDebugLog('VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return true;
      }
      if (words.contains('start prompt') ||
          words.contains('\u05D1\u05D5\u05D0')) {
        _addDebugLog('VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return true;
      }
      if (words.contains('speed up') || words.contains('\u05DE\u05D4\u05E8')) {
        _addDebugLog('VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return true;
      }
      if (words.contains('slow down') || words.contains('\u05DC\u05D0\u05D8')) {
        _addDebugLog('VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return true;
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'teleprompterProvider.voiceCommandSettings',
      );
    }
    return false;
  }

  AlignmentResult _bestAlignmentForTranscript({
    required Script script,
    required String transcript,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
    required int? maxSkipTargetIndex,
  }) {
    final windows = _recentTranscriptWindows(transcript);
    final alignmentWindows = windows.isEmpty ? [transcript] : windows;

    AlignmentResult align(String transcriptWindow) => WordAligner.align(
          script: script.words,
          transcript: transcriptWindow,
          lastConfirmedIndex: _currentState.confirmedWordIndex,
          visibleSkipStartIndex:
              maxSkipTargetIndex == null ? null : _visibleWordStart,
          maxSkipTargetIndex: maxSkipTargetIndex,
          strictBulletMode: strictBulletMode,
          policy: policy,
          readingStandby: _sttReadingStandby || _lockedOn,
        );

    var best = align(alignmentWindows.first);
    for (var i = 1; i < alignmentWindows.length; i++) {
      final candidate = align(alignmentWindows[i]);
      if (!_alignmentIsBetter(candidate, best)) continue;
      best = candidate.copyWith(
        debugInfo:
            '${candidate.debugInfo} | window=${i + 1}/${alignmentWindows.length}',
      );
    }
    return best;
  }

  bool _alignmentIsBetter(AlignmentResult candidate, AlignmentResult current) {
    if (candidate.shouldAdvance && !current.shouldAdvance) return true;
    if (!candidate.shouldAdvance || !current.shouldAdvance) return false;
    if (candidate.confirmedWordIndex != current.confirmedWordIndex) {
      return candidate.confirmedWordIndex > current.confirmedWordIndex;
    }
    return candidate.confidence > current.confidence;
  }

  void _handleMovementCandidate({
    required AlignmentResult aligned,
    required Script script,
    required SttRecognitionPolicy policy,
    required int? maxSkipTargetIndex,
    required String transcript,
    required String engineTag,
  }) {
    final currentIndex = _currentState.confirmedWordIndex;
    final guardIndex = _currentSttAdvanceGuardIndex(currentIndex);
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: aligned.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final decision = _movementPolicy.evaluateCandidate(
      alignment: aligned,
      policy: policy,
      trackingState: _sttEvidenceTrackingState,
      currentIndex: currentIndex,
      advanceGuardIndex: guardIndex,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
      maxLocalAdvanceWithoutWait:
          TeleprompterNotifier._maxLocalSttJumpWithoutWait,
    );

    if (!decision.shouldAdvance) {
      _applyMovementHoldOrReset(
        decision: decision,
        aligned: aligned,
        transcript: transcript,
        engineTag: engineTag,
      );
      if (_handlePoorAppleRecognitionIfNeeded(
        script: script,
        transcript: transcript,
      )) {
        return;
      }
      _maybeAssistVisibleLocale(script, policy, transcript);
      return;
    }

    final target = TeleprompterNotifier.resolveAdvanceTarget(
      currentIndex: currentIndex,
      alignedIndex: aligned.confirmedWordIndex,
      visibleMaxSkipTargetIndex:
          visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
    );
    _sttEvidenceTrackingState = decision.nextState;
    _lockedOn = true;
    _sttReadingStandby = true;
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
    _resetAppleRecognitionQuality();
    _resetVisibleLocaleAssist();

    _addTrackDebug(
      engineTag: engineTag,
      decision: decision,
      alignment: aligned.copyWith(confirmedWordIndex: target),
      transcript: transcript,
    );
    LightweightDiagnostics.instance.record(
      'stt',
      'track advanced',
      data: {
        'from': currentIndex,
        'to': target,
        'kind': aligned.kind.name,
        'family': aligned.thresholdFamily.name,
      },
    );
    _rememberPostAdvanceApplePartial(transcript, target);
    _applySttAdvanceTarget(target, script);
    _syncLocaleForPosition(script, target + 1, reason: 'advance');
  }

  void _handleNoMovementCandidate({
    required AlignmentResult aligned,
    required Script script,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
    required String transcript,
    required int spokenWordCount,
    required List<String> freshWords,
    required String engineTag,
  }) {
    final key = _noProgressTranscriptKey(transcript);
    final repeatedTranscript =
        key.isNotEmpty && key == _lastNoProgressTranscriptKey;
    final preserveSlowContext = WordAligner.shouldPreserveSlowContext(
      script: script.words,
      transcript: transcript,
      lastConfirmedIndex: _currentState.confirmedWordIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    var decision = _movementPolicy.evaluateNoCandidate(
      transcript: transcript,
      alignment: aligned,
      trackingState: _sttEvidenceTrackingState,
      preserveSlowContext: preserveSlowContext,
      repeatedTranscript: repeatedTranscript,
    );

    if (decision.shouldReset &&
        policy.safetyRecovery.evidenceScore(freshWords) <
            policy.safetyRecovery.smallWords) {
      decision = SttMovementDecision(
        action: SttMovementAction.hold,
        nextState: _sttEvidenceTrackingState,
        targetIndex: decision.targetIndex,
        label: 'TRACK_HOLD',
        reason: 'off_script_below_safety_threshold',
        thresholdLabel: 'safetyRecovery',
        evidenceScore: policy.safetyRecovery.evidenceScore(freshWords),
        neededScore: policy.safetyRecovery.smallWords.toDouble(),
      );
    }

    _applyMovementHoldOrReset(
      decision: decision,
      aligned: aligned,
      transcript: transcript,
      engineTag: engineTag,
      spokenWordCount: spokenWordCount,
    );
    if (_handlePoorAppleRecognitionIfNeeded(
        script: script, transcript: transcript)) {
      return;
    }
    _maybeAssistVisibleLocale(script, policy, transcript);
  }

  void _applyMovementHoldOrReset({
    required SttMovementDecision decision,
    required AlignmentResult aligned,
    required String transcript,
    required String engineTag,
    int? spokenWordCount,
  }) {
    if (decision.shouldReset) {
      _lockedOn = false;
      _sttReadingStandby = false;
      _sttEvidenceTrackingState = decision.nextState;
      if (spokenWordCount != null) _transcriptFloor = spokenWordCount;
      _noProgressCount = 0;
      _resetPostAdvancePartialGuard();
    } else {
      _sttEvidenceTrackingState = decision.nextState;
      if (!_lockedOn) _sttReadingStandby = false;
      if (!_noProgressTranscriptRepeated(transcript)) {
        _noProgressCount++;
      }
    }
    _addTrackDebug(
      engineTag: engineTag,
      decision: decision,
      alignment: aligned,
      transcript: transcript,
    );
  }

  bool _noProgressTranscriptRepeated(String transcript) {
    final key = _noProgressTranscriptKey(transcript);
    return key.isNotEmpty && key == _lastNoProgressTranscriptKey;
  }

  void _addTrackDebug({
    required String engineTag,
    required SttMovementDecision decision,
    required AlignmentResult alignment,
    required String transcript,
  }) {
    final heard = TeleprompterNotifier.debugTranscriptSnippet(transcript);
    final next = WordAligner.debugNextExpected(
      _currentScript?.words ?? const [],
      _currentState.confirmedWordIndex,
    );
    final details = <String>[
      decision.debugSummary,
      alignment.kind.name,
      if (alignment.confidence > 0)
        'conf=${alignment.confidence.toStringAsFixed(2)}',
      if (heard.isNotEmpty) 'heard="$heard"',
      if (!decision.shouldAdvance) 'next="$next"',
    ].join(' | ');
    _addDebugLog('$engineTag $details');
  }
}
