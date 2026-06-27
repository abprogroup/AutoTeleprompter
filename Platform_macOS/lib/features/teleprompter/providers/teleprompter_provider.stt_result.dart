part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttResult on TeleprompterNotifier {
  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      if (words.contains('stop prompt') ||
          words.contains('\u05E2\u05E6\u05D5\u05E8') ||
          words.contains('\u05E2\u05E6\u05D9\u05E8\u05D4')) {
        _addDebugLog('VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') ||
          words.contains('\u05D1\u05D5\u05D0')) {
        _addDebugLog('VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return;
      } else if (words.contains('speed up') ||
          words.contains('\u05DE\u05D4\u05E8')) {
        _addDebugLog('VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') ||
          words.contains('\u05DC\u05D0\u05D8')) {
        _addDebugLog('VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'teleprompterProvider.voiceCommandSettings',
      );
    }

    final rawTranscript = result.words;
    _accumulatedTranscript =
        TeleprompterNotifier.capTranscriptForRelock(rawTranscript);
    _maybeRenewAppleTranscriptSource(rawTranscript);
    final alignmentWindows = _recentTranscriptWindows(_accumulatedTranscript);
    var alignmentTranscript =
        alignmentWindows.isEmpty ? '' : alignmentWindows.first;
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

    AlignmentResult alignWindow(String transcriptWindow) => WordAligner.align(
          script: script.words,
          transcript: transcriptWindow,
          lastConfirmedIndex: _currentState.confirmedWordIndex,
          visibleSkipStartIndex:
              maxSkipTargetIndex == null ? null : _visibleWordStart,
          maxSkipTargetIndex: maxSkipTargetIndex,
          strictBulletMode: strictBulletMode,
          policy: policy,
          readingStandby: _sttReadingStandby,
        );

    var aligned = alignWindow(alignmentTranscript);
    if (!aligned.shouldAdvance &&
        !aligned.shouldEnterStandby &&
        alignmentWindows.length > 1) {
      for (var i = 1; i < alignmentWindows.length; i++) {
        final candidateTranscript = alignmentWindows[i];
        final candidate = alignWindow(candidateTranscript);
        if (candidate.shouldAdvance &&
            candidate.confirmedWordIndex > _currentState.confirmedWordIndex) {
          alignmentTranscript = candidateTranscript;
          aligned = candidate.copyWith(
            debugInfo:
                '${candidate.debugInfo} | rollingWindow=${i + 1}/${alignmentWindows.length}',
          );
          break;
        }
      }
    }

    final currentIdx = _currentState.confirmedWordIndex;
    final debugHeard =
        TeleprompterNotifier.debugTranscriptSnippet(alignmentTranscript);
    final nextExpected =
        WordAligner.debugNextExpected(script.words, currentIdx);
    final engineTag = _useWhisper ? '[Whisper]' : '[Speech]';

    final pendingStart = _pendingStartEvidenceContinuation(
      script: script,
      transcript: alignmentTranscript,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    if (pendingStart != null) {
      _handlePendingStartEvidenceCandidate(
        candidate: pendingStart,
        script: script,
        policy: policy,
        alignmentTranscript: alignmentTranscript,
        engineTag: engineTag,
      );
      return;
    }

    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _sttEvidenceTrackingState = SttEvidenceTrackingState.recovering;
      _noProgressCount = 0;
      _resetStaleNoProgressTracking();
      _resetAppleRecognitionQuality();
      _addDebugLog(
          '$engineTag STANDBY LOCK | ${aligned.debugInfo} | heard: "$debugHeard"');
      LightweightDiagnostics.instance.record(
        'stt',
        'standby lock',
        data: {
          'heard': alignmentTranscript,
          'position': _currentState.confirmedWordIndex,
          'confidence': aligned.confidence,
        },
      );
      return;
    }

    if (aligned.shouldAdvance &&
        aligned.confirmedWordIndex > _currentState.confirmedWordIndex) {
      _handleAlignedSttCandidate(
        aligned: aligned,
        script: script,
        policy: policy,
        maxSkipTargetIndex: maxSkipTargetIndex,
        alignmentTranscript: alignmentTranscript,
        debugHeard: debugHeard,
        engineTag: engineTag,
      );
      return;
    }

    final improvising = TeleprompterNotifier.shouldUseImprovisationNoMatch(
      strictBulletMode: strictBulletMode,
      alignedIndex: aligned.confirmedWordIndex,
      currentIndex: _currentState.confirmedWordIndex,
    );
    if (!strictBulletMode) {
      _sttReadingStandby = false;
    }

    final sequential = _consumeSequentialSttStreak(
      script: script,
      transcript: alignmentTranscript,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    if (sequential != null) {
      if (sequential.targetIndex != null &&
          sequential.targetIndex! > _currentState.confirmedWordIndex) {
        _handleSequentialSttCandidate(
          sequential: sequential,
          script: script,
          policy: policy,
          alignmentTranscript: alignmentTranscript,
          engineTag: engineTag,
        );
        return;
      }

      _noProgressCount = 0;
      _resetStaleNoProgressTracking();
      _resetAppleRecognitionQuality();
      _sttReadingStandby = true;
      _addDebugLog('$engineTag SEQUENTIAL HOLD | ${sequential.debugInfo}');
      return;
    }

    final noMatchGate = _evaluateSttNoMatchGate(
      transcript: alignmentTranscript,
      alignment: aligned,
      script: script,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    _applyGateState(noMatchGate);
    _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
      currentCount: _noProgressCount,
      improvising: improvising || noMatchGate.shouldReset,
      visibleAssistThreshold:
          TeleprompterNotifier._visibleLocaleAssistAfterWaits,
    );
    if (improvising || noMatchGate.shouldReset) {
      _addDebugLog(
          '$engineTag ${noMatchGate.debugSummary} | heard: "$debugHeard" | visible relock waiting');
      LightweightDiagnostics.instance.record(
        'stt',
        'gate no match ${noMatchGate.action.name}',
        data: {
          'heard': alignmentTranscript,
          'position': currentIdx,
          'reason': noMatchGate.reason,
        },
      );
    } else {
      _addDebugLog(
          '$engineTag WAIT #$_noProgressCount | heard: "$debugHeard" | next: "$nextExpected"');
      LightweightDiagnostics.instance.record(
        'stt',
        'waiting',
        data: {
          'heard': alignmentTranscript,
          'next': nextExpected,
          'position': currentIdx,
          'stuckCount': _noProgressCount,
        },
      );
      _checkAndSwitchLocale();
    }

    final relockTranscript = _accumulatedTranscript.trim().isEmpty
        ? alignmentTranscript
        : _accumulatedTranscript;
    final relockTarget =
        _relockTargetFromTranscript(script, relockTranscript, policy);
    if (relockTarget != null &&
        relockTarget > _currentState.confirmedWordIndex) {
      _handleRelockSttCandidate(
        relockTarget: relockTarget,
        script: script,
        policy: policy,
        relockTranscript: relockTranscript,
        engineTag: engineTag,
      );
      return;
    }

    if (_handlePoorAppleRecognitionIfNeeded(
      script: script,
      transcript: alignmentTranscript,
    )) {
      return;
    }

    if (_maybeAssistVisibleLocale(script, policy, alignmentTranscript)) {
      return;
    }
  }

  void _handleAlignedSttCandidate({
    required AlignmentResult aligned,
    required Script script,
    required SttRecognitionPolicy policy,
    required int? maxSkipTargetIndex,
    required String alignmentTranscript,
    required String debugHeard,
    required String engineTag,
  }) {
    final advanceFrom = _currentState.confirmedWordIndex;
    final advanceGuardFrom = _currentSttAdvanceGuardIndex(advanceFrom);
    if (aligned.confirmedWordIndex <= advanceGuardFrom) return;
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: aligned.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final gateDecision = _evaluateSttGate(
      candidate: SttEvidenceGateCandidate.fromAlignment(aligned),
      policy: policy,
      currentIndex: advanceFrom,
      advanceGuardIndex: advanceGuardFrom,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
    );
    if (!gateDecision.shouldAdvance) {
      _rememberPendingStartEvidence(
        decision: gateDecision,
        candidate: SttEvidenceGateCandidate.fromAlignment(aligned),
        currentIndex: advanceFrom,
      );
      _applyGateState(gateDecision);
      _fluidAdvanceTimer?.cancel();
      _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
        currentCount: _noProgressCount,
        improvising: gateDecision.shouldReset,
        visibleAssistThreshold:
            TeleprompterNotifier._visibleLocaleAssistAfterWaits,
      );
      _addDebugLog(
        '$engineTag ${gateDecision.debugSummary} | ${aligned.debugInfo} | heard: "$debugHeard"',
      );
      LightweightDiagnostics.instance.record(
        'stt',
        'gate ${gateDecision.action.name}',
        data: {
          'from': advanceFrom,
          'aligned': aligned.confirmedWordIndex,
          'state': _sttEvidenceTrackingState.name,
          'reason': gateDecision.reason,
          'visibleStart': _visibleWordStart,
          'visibleEnd': _visibleWordEnd,
          'heard': alignmentTranscript,
        },
      );
      return;
    }

    _applyGateState(gateDecision);
    _sttReadingStandby = true;
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
    _resetAppleRecognitionQuality();
    _resetVisibleLocaleAssist();
    final target = TeleprompterNotifier.resolveAdvanceTarget(
      currentIndex: advanceFrom,
      alignedIndex: aligned.confirmedWordIndex,
      visibleMaxSkipTargetIndex:
          visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
    );
    final advancedWord =
        target < script.words.length ? script.words[target].raw : '?';
    final alignReason = aligned.debugInfo.startsWith('NAME_ANCHOR') ||
            SttRecognitionPolicyService.isLocalStructuralAlignment(
              aligned.debugInfo,
            )
        ? ' | ${aligned.debugInfo}'
        : '';
    _addDebugLog(
        '$engineTag ${gateDecision.debugSummary} -> #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)})$alignReason | heard: "$debugHeard"');
    LightweightDiagnostics.instance.record(
      'stt',
      'advanced',
      data: {
        'from': _currentState.confirmedWordIndex,
        'to': target,
        'word': advancedWord,
        'confidence': aligned.confidence,
        'heard': alignmentTranscript,
      },
    );

    _applySttAdvanceTarget(target, script);
    _syncLocaleForPosition(script, target + 1, reason: 'advance');
  }

  void _handleSequentialSttCandidate({
    required _SequentialSttProgress sequential,
    required Script script,
    required SttRecognitionPolicy policy,
    required String alignmentTranscript,
    required String engineTag,
  }) {
    final advanceFrom = _currentState.confirmedWordIndex;
    final target = sequential.targetIndex!;
    final advanceGuardFrom = _currentSttAdvanceGuardIndex(advanceFrom);
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: target,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final gateDecision = _evaluateSttGate(
      candidate: _sequentialGateCandidate(sequential),
      policy: policy,
      currentIndex: advanceFrom,
      advanceGuardIndex: advanceGuardFrom,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
    );
    if (!gateDecision.shouldAdvance) {
      _applyGateState(gateDecision);
      _addDebugLog(
        '$engineTag ${gateDecision.debugSummary} | SEQUENTIAL ${sequential.debugInfo}',
      );
      LightweightDiagnostics.instance.record(
        'stt',
        'sequential gate ${gateDecision.action.name}',
        data: {
          'to': target,
          'heard': alignmentTranscript,
          'debug': sequential.debugInfo,
          'reason': gateDecision.reason,
        },
      );
      return;
    }
    final advancedWord =
        target < script.words.length ? script.words[target].raw : '?';
    _applyGateState(gateDecision);
    _fluidAdvanceTimer?.cancel();
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
    _resetAppleRecognitionQuality();
    _sttReadingStandby = true;
    _resetVisibleLocaleAssist();
    _addDebugLog(
      '$engineTag ${gateDecision.debugSummary} -> #$target "$advancedWord" | SEQUENTIAL ${sequential.debugInfo}',
    );
    LightweightDiagnostics.instance.record(
      'stt',
      'sequential advanced',
      data: {
        'to': target,
        'word': advancedWord,
        'heard': alignmentTranscript,
        'debug': sequential.debugInfo,
      },
    );
    _applySttAdvanceTarget(target, script);
    _syncLocaleForPosition(script, target + 1, reason: 'sequential');
  }

  void _handlePendingStartEvidenceCandidate({
    required SttEvidenceGateCandidate candidate,
    required Script script,
    required SttRecognitionPolicy policy,
    required String alignmentTranscript,
    required String engineTag,
  }) {
    final advanceFrom = _currentState.confirmedWordIndex;
    final advanceGuardFrom = _currentSttAdvanceGuardIndex(advanceFrom);
    if (candidate.targetIndex <= advanceGuardFrom) return;
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: candidate.targetIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final gateDecision = _evaluateSttGate(
      candidate: candidate,
      policy: policy,
      currentIndex: advanceFrom,
      advanceGuardIndex: advanceGuardFrom,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
    );
    final debugHeard =
        TeleprompterNotifier.debugTranscriptSnippet(alignmentTranscript);
    if (!gateDecision.shouldAdvance) {
      _rememberPendingStartEvidence(
        decision: gateDecision,
        candidate: candidate,
        currentIndex: advanceFrom,
      );
      _applyGateState(gateDecision);
      _addDebugLog(
        '$engineTag ${gateDecision.debugSummary} | ${candidate.debugInfo} | heard: "$debugHeard"',
      );
      return;
    }

    _applyGateState(gateDecision);
    _sttReadingStandby = true;
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
    _resetAppleRecognitionQuality();
    _resetVisibleLocaleAssist();
    final target = TeleprompterNotifier.resolveAdvanceTarget(
      currentIndex: advanceFrom,
      alignedIndex: candidate.targetIndex,
      visibleMaxSkipTargetIndex:
          visibleSkipTargetTrusted ? _visibleWordEnd : null,
    );
    final advancedWord =
        target < script.words.length ? script.words[target].raw : '?';
    _addDebugLog(
      '$engineTag ${gateDecision.debugSummary} -> #$target "$advancedWord" '
      '| CONTINUED_START ${candidate.debugInfo} | heard: "$debugHeard"',
    );
    LightweightDiagnostics.instance.record(
      'stt',
      'continued start advanced',
      data: {
        'from': advanceFrom,
        'to': target,
        'heard': alignmentTranscript,
        'debug': candidate.debugInfo,
      },
    );
    _applySttAdvanceTarget(target, script);
    _syncLocaleForPosition(script, target + 1, reason: 'continued start');
  }

  void _handleRelockSttCandidate({
    required int relockTarget,
    required Script script,
    required SttRecognitionPolicy policy,
    required String relockTranscript,
    required String engineTag,
  }) {
    final relockFrom = _currentState.confirmedWordIndex;
    final relockGuardFrom = _currentSttAdvanceGuardIndex(relockFrom);
    if (relockTarget <= relockGuardFrom) return;
    final relockVisibleTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: relockTarget,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    final relockGateDecision = _evaluateSttGate(
      candidate: _relockGateCandidate(
        targetIndex: relockTarget,
        transcript: relockTranscript,
        policy: policy,
      ),
      policy: policy,
      currentIndex: relockFrom,
      advanceGuardIndex: relockGuardFrom,
      visibleSkipTargetTrusted: relockVisibleTrusted,
    );
    if (!relockGateDecision.shouldAdvance) {
      _applyGateState(relockGateDecision);
      _fluidAdvanceTimer?.cancel();
      _resetSequentialSttStreak();
      final relockJump = relockTarget - relockGuardFrom;
      final debugRelockHeard =
          TeleprompterNotifier.debugTranscriptSnippet(relockTranscript);
      _addDebugLog(
        '$engineTag ${relockGateDecision.debugSummary} | delayed ${_lastRelockScope.toUpperCase()} relock '
        '+$relockJump ->$relockTarget | heard: "$debugRelockHeard"',
      );
      LightweightDiagnostics.instance.record(
        'stt',
        'relock gate ${relockGateDecision.action.name}',
        data: {
          'from': relockFrom,
          'to': relockTarget,
          'jump': relockJump,
          'scope': _lastRelockScope,
          'heard': relockTranscript,
          'reason': relockGateDecision.reason,
        },
      );
      return;
    }
    _applyGateState(relockGateDecision);
    final relockedWord = script.words[relockTarget].raw;
    final debugRelockHeard =
        TeleprompterNotifier.debugTranscriptSnippet(relockTranscript);
    _addDebugLog(
      '$engineTag ${relockGateDecision.debugSummary} | RELOCK ${_lastRelockScope.toUpperCase()} -> #$relockTarget "$relockedWord" | heard: "$debugRelockHeard"',
    );
    LightweightDiagnostics.instance.record(
      'stt',
      'relocked',
      data: {
        'from': _currentState.confirmedWordIndex,
        'to': relockTarget,
        'word': relockedWord,
        'scope': _lastRelockScope,
        'heard': relockTranscript,
      },
    );
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
    _resetAppleRecognitionQuality();
    _sttReadingStandby = true;
    _applySttAdvanceTarget(relockTarget, script);
    _syncLocaleForPosition(script, relockTarget + 1, reason: 'relock');
  }
}
