part of 'teleprompter_provider.dart';

extension TeleprompterNotifierStt on TeleprompterNotifier {
  static const _transcriptBuffer = SttTranscriptBufferService();
  static const _movementPolicy = SttMovementPolicyService();
  static const _visibleSkipContext = SttVisibleSkipContextService();

  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));
    if (_handleVoiceCommand(result.words)) return;

    final buffer = _transcriptBuffer.update(
      rawTranscript: result.words,
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
      scriptWordCount: script.words.length,
      sustainedStuck: _isSustainedlyStuck,
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
        spokenWordCount: buffer.spokenWords.length,
        engineTag: engineTag,
      );
      return;
    }

    _handleNoMovementCandidate(
      aligned: aligned,
      script: script,
      policy: policy,
      strictBulletMode: strictBulletMode,
      maxSkipTargetIndex: maxSkipTargetIndex,
      transcript: _accumulatedTranscript,
      spokenWordCount: buffer.spokenWords.length,
      engineTag: engineTag,
    );
  }

  bool _handleVoiceCommand(String rawWords) {
    final words = rawWords.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);
      if (words.contains('stop prompt') ||
          words.contains('עצור') ||
          words.contains('עצירה')) {
        _addDebugLog('VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return true;
      }
      if (words.contains('start prompt') || words.contains('בוא')) {
        _addDebugLog('VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return true;
      }
      if (words.contains('speed up') || words.contains('מהר')) {
        _addDebugLog('VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return true;
      }
      if (words.contains('slow down') || words.contains('לאט')) {
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
    final pendingStartTarget = _pendingStartEvidenceTargetIndex;

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

    AlignmentResult? continuePendingStart(String transcriptWindow) {
      if (pendingStartTarget == null ||
          pendingStartTarget <= _currentState.confirmedWordIndex) {
        return null;
      }
      return WordAligner.continuePendingStartEvidence(
        script: script.words,
        transcript: transcriptWindow,
        pendingTargetIndex: pendingStartTarget,
        strictBulletMode: strictBulletMode,
      );
    }

    var best = align(alignmentWindows.first);
    final firstPending = continuePendingStart(alignmentWindows.first);
    if (firstPending != null && _alignmentIsBetter(firstPending, best)) {
      best = firstPending;
    }
    for (var i = 1; i < alignmentWindows.length; i++) {
      final candidate = align(alignmentWindows[i]);
      if (_alignmentIsBetter(candidate, best)) {
        best = candidate.copyWith(
          debugInfo:
              '${candidate.debugInfo} | rollingWindow=${i + 1}/${alignmentWindows.length}',
        );
      }
      final pendingCandidate = continuePendingStart(alignmentWindows[i]);
      if (pendingCandidate == null ||
          !_alignmentIsBetter(pendingCandidate, best)) {
        continue;
      }
      best = pendingCandidate.copyWith(
        debugInfo:
            '${pendingCandidate.debugInfo} | window=${i + 1}/${alignmentWindows.length}',
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
    required int spokenWordCount,
    required String engineTag,
  }) {
    final currentIndex = _currentState.confirmedWordIndex;
    final previousTrackingState = _sttEvidenceTrackingState;
    final guardIndex = _currentSttAdvanceGuardIndex(currentIndex);
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: aligned.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: maxSkipTargetIndex ?? _visibleWordEnd,
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
      if (_maybeAdvancePendingVisibleSkip(
        script: script,
        policy: policy,
        strictBulletMode: false,
        maxSkipTargetIndex: maxSkipTargetIndex,
        transcript: transcript,
        spokenWordCount: spokenWordCount,
        engineTag: engineTag,
      )) {
        return;
      }
      _rememberVisibleSkipEvidenceIfNeeded(
        decision: decision,
        transcript: transcript,
        currentIndex: currentIndex,
      );
      _applyMovementHoldOrReset(
        decision: decision,
        aligned: aligned,
        transcript: transcript,
        engineTag: engineTag,
      );
      _maybeAssistVisibleLocale(script, policy, transcript);
      return;
    }

    _applyMovementAdvance(
      decision: decision,
      aligned: aligned,
      script: script,
      maxSkipTargetIndex: maxSkipTargetIndex,
      transcript: transcript,
      spokenWordCount: spokenWordCount,
      engineTag: engineTag,
      previousTrackingState: previousTrackingState,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
    );
  }

  void _applyMovementAdvance({
    required SttMovementDecision decision,
    required AlignmentResult aligned,
    required Script script,
    required int? maxSkipTargetIndex,
    required String transcript,
    required int spokenWordCount,
    required String engineTag,
    required SttEvidenceTrackingState previousTrackingState,
    required bool visibleSkipTargetTrusted,
  }) {
    final currentIndex = _currentState.confirmedWordIndex;
    final target = TeleprompterNotifier.resolveAdvanceTarget(
      currentIndex: currentIndex,
      alignedIndex: aligned.confirmedWordIndex,
      visibleMaxSkipTargetIndex:
          visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
    );
    _pendingStartEvidenceTargetIndex = null;
    _clearPendingVisibleSkipEvidence();
    _sttEvidenceTrackingState = decision.nextState;
    _lastConfirmedAdvanceAt = DateTime.now();
    _lockedOn = true;
    _sttReadingStandby = true;
    if (previousTrackingState == SttEvidenceTrackingState.locked ||
        previousTrackingState == SttEvidenceTrackingState.offScript) {
      _transcriptFloor = spokenWordCount;
    }
    _noProgressCount = 0;
    _resetStaleNoProgressTracking();
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
    _applySttAdvanceTarget(target, script);
    _syncLocaleForPosition(script, target + 1, reason: 'advance');
  }

  void _handleNoMovementCandidate({
    required AlignmentResult aligned,
    required Script script,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
    required int? maxSkipTargetIndex,
    required String transcript,
    required int spokenWordCount,
    required String engineTag,
  }) {
    _checkAndSwitchLocale();
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

    if (_maybeAdvancePendingVisibleSkip(
      script: script,
      policy: policy,
      strictBulletMode: strictBulletMode,
      maxSkipTargetIndex: maxSkipTargetIndex,
      transcript: transcript,
      spokenWordCount: spokenWordCount,
      engineTag: engineTag,
    )) {
      return;
    }

    if (decision.shouldReset && _pendingStartEvidenceTargetIndex != null) {
      decision = SttMovementDecision(
        action: SttMovementAction.hold,
        nextState: _sttEvidenceTrackingState,
        targetIndex: _pendingStartEvidenceTargetIndex!,
        label: 'TRACK_HOLD',
        reason: 'pending_start_waiting',
        thresholdLabel: 'startAdvance',
        evidenceScore: policy.safetyRecovery.evidenceScore(
          transcript
              .split(RegExp(r'\s+'))
              .map((word) => word.trim().normalizeForMatching())
              .where((word) => word.isNotEmpty)
              .toList(growable: false),
        ),
        neededScore: policy.startAdvance.smallWords.toDouble(),
      );
    } else if (decision.shouldReset &&
        _visibleSkipContext.shouldPreserve(
          script: script.words,
          transcript: transcript,
          lastConfirmedIndex: _currentState.confirmedWordIndex,
          visibleSkipStartIndex: _visibleWordStart,
          maxSkipTargetIndex: maxSkipTargetIndex,
          policy: policy,
          strictBulletMode: strictBulletMode,
        )) {
      _rememberPendingVisibleSkipTranscript(
        transcript: transcript,
        currentIndex: _currentState.confirmedWordIndex,
      );
      decision = SttMovementDecision(
        action: SttMovementAction.hold,
        nextState: _sttEvidenceTrackingState,
        targetIndex: _currentState.confirmedWordIndex,
        label: 'TRACK_HOLD',
        reason: 'visible_skip_evidence_waiting',
        thresholdLabel: 'visibleSkip',
        evidenceScore: 0,
        neededScore: policy.visibleSkip.smallWords.toDouble(),
      );
    } else if (decision.shouldReset) {
      _clearPendingVisibleSkipEvidence();
    }

    _applyMovementHoldOrReset(
      decision: decision,
      aligned: aligned,
      transcript: transcript,
      engineTag: engineTag,
      spokenWordCount: spokenWordCount,
    );
    _maybeAssistVisibleLocale(script, policy, transcript);
  }

  void _applyMovementHoldOrReset({
    required SttMovementDecision decision,
    required AlignmentResult aligned,
    required String transcript,
    required String engineTag,
    int? spokenWordCount,
  }) {
    _rememberPendingStartEvidenceIfNeeded(decision, aligned);
    if (decision.shouldReset) {
      _lockedOn = false;
      _sttReadingStandby = false;
      _sttEvidenceTrackingState = decision.nextState;
      if (spokenWordCount != null) _transcriptFloor = spokenWordCount;
      _pendingStartEvidenceTargetIndex = null;
      _clearPendingVisibleSkipEvidence();
      _noProgressCount = 0;
    } else {
      _sttEvidenceTrackingState = decision.nextState;
      if (!_lockedOn) _sttReadingStandby = false;
      if (_recordNoProgressTranscript(transcript) <= 1) {
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

  void _rememberPendingStartEvidenceIfNeeded(
    SttMovementDecision decision,
    AlignmentResult alignment,
  ) {
    if (decision.action != SttMovementAction.hold ||
        decision.thresholdLabel != 'startAdvance' ||
        !alignment.shouldAdvance ||
        decision.evidenceScore <= 0 ||
        decision.targetIndex <= _currentState.confirmedWordIndex ||
        alignment.debugInfo.startsWith('CONTINUED_START')) {
      return;
    }
    _pendingStartEvidenceTargetIndex ??= decision.targetIndex;
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

  void _addTrackDebug({
    required String engineTag,
    required SttMovementDecision decision,
    required AlignmentResult alignment,
    required String transcript,
  }) {
    final next = WordAligner.debugNextExpected(
      _currentScript?.words ?? const [],
      _currentState.confirmedWordIndex,
    );
    final details = <String>[
      decision.debugSummary,
      alignment.kind.name,
      if (alignment.confidence > 0)
        'conf=${alignment.confidence.toStringAsFixed(2)}',
      if (transcript.isNotEmpty) 'heard="$transcript"',
      if (!decision.shouldAdvance) 'next="$next"',
    ].join(' | ');
    _addDebugLog('$engineTag $details');
  }

  bool _maybeAdvancePendingVisibleSkip({
    required Script script,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
    required int? maxSkipTargetIndex,
    required String transcript,
    required int spokenWordCount,
    required String engineTag,
  }) {
    final pending = _pendingVisibleSkipTranscript;
    if (pending.trim().isEmpty || maxSkipTargetIndex == null) return false;
    if (_pendingVisibleSkipOriginIndex != _currentState.confirmedWordIndex ||
        _pendingVisibleSkipStartIndex != _visibleWordStart ||
        _pendingVisibleSkipEndIndex != maxSkipTargetIndex) {
      _clearPendingVisibleSkipEvidence();
      return false;
    }
    final mergedTranscript = _visibleSkipContext.mergePendingTranscript(
      pendingTranscript: pending,
      transcript: transcript,
    );
    final rescue = _visibleSkipContext.rescueAlignment(
      script: script.words,
      pendingTranscript: pending,
      transcript: transcript,
      lastConfirmedIndex: _currentState.confirmedWordIndex,
      visibleSkipStartIndex: _visibleWordStart,
      maxSkipTargetIndex: maxSkipTargetIndex,
      policy: policy,
      strictBulletMode: strictBulletMode,
    );
    if (rescue == null) {
      _rememberPendingVisibleSkipTranscript(
        transcript: transcript,
        currentIndex: _currentState.confirmedWordIndex,
      );
      return false;
    }
    final visibleSkipTargetTrusted =
        TeleprompterNotifier.isTrustedVisibleSkipTarget(
      alignedIndex: rescue.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: maxSkipTargetIndex,
    );
    final decision = _movementPolicy.evaluateCandidate(
      alignment: rescue,
      policy: policy,
      trackingState: _sttEvidenceTrackingState,
      currentIndex: _currentState.confirmedWordIndex,
      advanceGuardIndex: _currentSttAdvanceGuardIndex(
        _currentState.confirmedWordIndex,
      ),
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
      maxLocalAdvanceWithoutWait:
          TeleprompterNotifier._maxLocalSttJumpWithoutWait,
    );
    if (!decision.shouldAdvance) {
      _rememberPendingVisibleSkipTranscript(
        transcript: transcript,
        currentIndex: _currentState.confirmedWordIndex,
      );
      return false;
    }
    _applyMovementAdvance(
      decision: decision,
      aligned: rescue,
      script: script,
      maxSkipTargetIndex: maxSkipTargetIndex,
      transcript: mergedTranscript,
      spokenWordCount: spokenWordCount,
      engineTag: engineTag,
      previousTrackingState: _sttEvidenceTrackingState,
      visibleSkipTargetTrusted: visibleSkipTargetTrusted,
    );
    return true;
  }

  void _rememberVisibleSkipEvidenceIfNeeded({
    required SttMovementDecision decision,
    required String transcript,
    required int currentIndex,
  }) {
    if (decision.thresholdLabel != 'visibleSkip' ||
        decision.evidenceScore <= 0) {
      return;
    }
    _rememberPendingVisibleSkipTranscript(
      transcript: transcript,
      currentIndex: currentIndex,
    );
  }

  void _rememberPendingVisibleSkipTranscript({
    required String transcript,
    required int currentIndex,
  }) {
    if (transcript.trim().isEmpty || _visibleWordStart == null) return;
    _pendingVisibleSkipOriginIndex = currentIndex;
    _pendingVisibleSkipStartIndex = _visibleWordStart;
    _pendingVisibleSkipEndIndex = _visibleWordEnd;
    _pendingVisibleSkipTranscript = _visibleSkipContext.mergePendingTranscript(
      pendingTranscript: _pendingVisibleSkipTranscript,
      transcript: transcript,
    );
  }

  /// Advances instantly for a single local step; animates word-by-word
  /// through intermediate words for a trusted multi-word jump.
  void _applySttAdvanceTarget(int target, Script script) {
    final current = _currentState.confirmedWordIndex;
    if (target <= current) return;

    final nextSpeakable = WordAligner.nextSpeakableIndex(
      script.words,
      current + 1,
    );
    if (target <= nextSpeakable || nextSpeakable >= script.words.length) {
      _fluidAdvanceTimer?.cancel();
      _safeSetState((s) => s.copyWith(confirmedWordIndex: target));
      return;
    }

    _startFluidAdvance(target, script);
  }

  /// Animate word advancement from current position to [target],
  /// advancing one word every ~80ms so the eye can follow.
  void _startFluidAdvance(int target, Script script) {
    _fluidAdvanceTimer?.cancel();
    _fluidTarget = target;

    _fluidAdvanceTimer =
        Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_disposed || _sessionStopped) {
        timer.cancel();
        return;
      }
      final current = _currentState.confirmedWordIndex;

      // If a newer result pushed the target further, follow it
      final effectiveTarget = _fluidTarget;

      if (current >= effectiveTarget) {
        timer.cancel();
        return;
      }

      // Advance to next non-newline word
      int next = current + 1;
      while (next < script.words.length && script.words[next].isNewline) {
        next++;
      }
      if (next > effectiveTarget) next = effectiveTarget;

      _safeSetState((s) => s.copyWith(confirmedWordIndex: next));
    });
  }
}
