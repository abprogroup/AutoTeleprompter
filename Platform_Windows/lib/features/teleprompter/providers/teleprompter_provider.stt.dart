part of 'teleprompter_provider.dart';

extension TeleprompterNotifierStt on TeleprompterNotifier {
  void _handleSttResult(SpeechResult result) {
    if (_currentScript == null || _disposed) return;
    _safeSetState((s) => s.copyWith(isStarting: false));

    final words = result.words.toLowerCase();
    try {
      final settings = ref.read(settingsProvider);

      // Voice Commands
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

    _accumulatedTranscript =
        TeleprompterNotifier.capTranscriptForRelock(result.words);
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
          aligned = AlignmentResult(
            candidate.confirmedWordIndex,
            candidate.confidence,
            '${candidate.debugInfo} | rollingWindow=${i + 1}/${alignmentWindows.length}',
            candidate.decision,
          );
          break;
        }
      }
    }

    final currentIdx = _currentState.confirmedWordIndex;
    final nextExpected = (currentIdx + 1 < script.words.length)
        ? script.words
            .skip(currentIdx + 1)
            .where((w) => !w.isNewline)
            .take(3)
            .map((w) => w.raw)
            .join(' ')
        : '<END>';

    final engineTag = _useWhisper ? '[Whisper]' : '[Speech]';
    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      _addDebugLog(
          '$engineTag STANDBY LOCK | ${aligned.debugInfo} | heard: "$alignmentTranscript"');
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
      final advanceFrom = _currentState.confirmedWordIndex;
      final visibleSkipTargetTrusted =
          TeleprompterNotifier.isTrustedVisibleSkipTarget(
        alignedIndex: aligned.confirmedWordIndex,
        visibleWordStart: _visibleWordStart,
        visibleWordEnd: _visibleWordEnd,
      );
      final rawJump = aligned.confirmedWordIndex - advanceFrom;
      if (!visibleSkipTargetTrusted && rawJump > 5) {
        _fluidAdvanceTimer?.cancel();
        if (!strictBulletMode) {
          _sttReadingStandby = false;
        }
        _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
          currentCount: _noProgressCount,
          improvising: false,
          visibleAssistThreshold:
              TeleprompterNotifier._visibleLocaleAssistAfterWaits,
        );
        _addDebugLog(
          '$engineTag WAIT #$_noProgressCount | blocked off-screen advance '
          '->${aligned.confirmedWordIndex} | heard: "$alignmentTranscript"',
        );
        LightweightDiagnostics.instance.record(
          'stt',
          'blocked off-screen advance',
          data: {
            'from': advanceFrom,
            'aligned': aligned.confirmedWordIndex,
            'visibleStart': _visibleWordStart,
            'visibleEnd': _visibleWordEnd,
            'heard': alignmentTranscript,
          },
        );
        return;
      }

      _sttReadingStandby = true;
      _noProgressCount = 0;
      _resetVisibleLocaleAssist();
      final target = TeleprompterNotifier.resolveAdvanceTarget(
        currentIndex: advanceFrom,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex:
            visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
      );
      final advancedWord =
          target < script.words.length ? script.words[target].raw : '?';
      _addDebugLog(
          '$engineTag ADVANCE -> #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "$alignmentTranscript"');
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

      // Fluid advancement: if jumping more than 3 words, animate
      // through intermediate words so the user's eye can follow.
      final jump = target - advanceFrom;
      if (visibleSkipTargetTrusted || jump <= 5) {
        // Small jumps and trusted visible-skip targets are instant.
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: target));
      } else {
        // Large jump - advance word by word with short delays.
        _startFluidAdvance(target, script);
      }
      _syncLocaleForPosition(script, target + 1, reason: 'advance');
    } else {
      final improvising = TeleprompterNotifier.shouldUseImprovisationNoMatch(
        strictBulletMode: strictBulletMode,
        alignedIndex: aligned.confirmedWordIndex,
        currentIndex: _currentState.confirmedWordIndex,
      );
      if (!strictBulletMode) {
        _sttReadingStandby = false;
      }
      _noProgressCount = TeleprompterNotifier.nextNoProgressCount(
        currentCount: _noProgressCount,
        improvising: improvising,
        visibleAssistThreshold:
            TeleprompterNotifier._visibleLocaleAssistAfterWaits,
      );
      if (improvising) {
        _addDebugLog(
            '$engineTag IMPROVISING | heard: "$alignmentTranscript" | visible relock waiting');
        LightweightDiagnostics.instance.record(
          'stt',
          'improvising',
          data: {'heard': alignmentTranscript, 'position': currentIdx},
        );
      } else {
        _addDebugLog(
            '$engineTag WAIT #$_noProgressCount | heard: "$alignmentTranscript" | next: "$nextExpected"');
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
      final relockTarget = _relockTargetFromTranscript(
        script,
        relockTranscript,
      );
      if (relockTarget != null &&
          relockTarget > _currentState.confirmedWordIndex) {
        final relockedWord = script.words[relockTarget].raw;
        _addDebugLog(
          '$engineTag RELOCK ${_lastRelockScope.toUpperCase()} -> #$relockTarget "$relockedWord" | heard: "$relockTranscript"',
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
        _sttReadingStandby = true;
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: relockTarget));
        _syncLocaleForPosition(script, relockTarget + 1, reason: 'relock');
        return;
      }

      if (_maybeAssistVisibleLocale(script, policy, alignmentTranscript)) {
        return;
      }
    }
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

  /// Current metadata safely resolves Hebrew/RTL and English/LTR only.
  /// Neutral tokens such as punctuation, brackets, dashes, dates, and numbers
  /// do not own a language. They inherit nearby real word context so `15.10`
  /// starts Hebrew STT in a Hebrew paragraph and English STT in English text.

  void _precomputeSectionLocales(Script script) {
    _sectionLocales = TeleprompterNotifier.resolveSectionLocalesForWords(
      script.words,
    );
  }

  void _checkAndSwitchLocale() {
    if (_useWhisper || _disposed || _sessionStopped) return;
    if (_visibleLocaleAssistPinActive()) return;
    if (_sectionLocales.isEmpty) return;
    final currentIdx = _currentState.confirmedWordIndex;
    if (currentIdx < 0 || currentIdx >= _sectionLocales.length) return;

    final lookIdx =
        (currentIdx + 1).clamp(0, _sectionLocales.length - 1).toInt();
    final needed = _sectionLocales[lookIdx];
    _switchLocaleIfNeeded(needed, reason: 'pre-switch');
  }

  void _syncLocaleForPosition(Script script, int wordIndex,
      {required String reason}) {
    if (_useWhisper || _disposed || _sessionStopped) return;
    if (_visibleLocaleAssistPinActive()) return;
    if (_sectionLocales.length != script.words.length) {
      _precomputeSectionLocales(script);
    }
    if (_sectionLocales.isEmpty) return;
    final lookIdx = wordIndex.clamp(0, _sectionLocales.length - 1).toInt();
    final needed = _sectionLocales[lookIdx];
    _switchLocaleIfNeeded(needed, reason: reason);
  }

  bool _switchLocaleIfNeeded(String locale, {required String reason}) {
    if (_useWhisper || _disposed || _sessionStopped) return false;
    if (!_activeSttCanSwitchLocale) return false;
    if (locale == _activeLocale && locale == _scriptLanguageLocale) {
      return false;
    }
    final previous = _activeLocale ?? _scriptLanguageLocale ?? '?';
    _activeLocale = locale;
    _scriptLanguageLocale = locale;
    _accumulatedTranscript = '';
    _sttReadingStandby = false;
    final engineName = _sttService.platformName.toUpperCase();
    _addDebugLog('STT LOCALE [$engineName]: $previous -> $locale ($reason)');
    _safeSetState((s) => s.copyWith(isStarting: true, soundLevel: 0.0));
    _sttService.setLocale(locale);
    return true;
  }

  bool _maybeAssistVisibleLocale(
    Script script,
    SttRecognitionPolicy policy,
    String heard,
  ) {
    if (_useWhisper || _disposed || _sessionStopped) return false;
    if (!policy.visibleSkipEnabled || heard.trim().isEmpty) {
      return false;
    }
    if (_visibleWordStart == null || _visibleWordEnd == null) return false;
    if (_visibleLocaleAssistPinActive()) return false;
    if (_sectionLocales.length != script.words.length) {
      _precomputeSectionLocales(script);
    }
    if (_sectionLocales.isEmpty) return false;

    final active = _activeLocale ?? _scriptLanguageLocale;
    if (active != null &&
        TeleprompterNotifier.visibleTranscriptPlausiblyMatchesLocale(
          words: script.words,
          sectionLocales: _sectionLocales,
          locale: active,
          transcript: heard,
          visibleStart: _visibleWordStart!,
          visibleEnd: _visibleWordEnd!,
          currentIndex: _currentState.confirmedWordIndex,
        )) {
      _pendingVisibleLocaleAssistLocale = null;
      return false;
    }

    final candidate = _nextVisibleLocaleCandidate(script);
    if (candidate == null || candidate == _activeLocale) {
      _pendingVisibleLocaleAssistLocale = null;
      return false;
    }

    if (_pendingVisibleLocaleAssistLocale != candidate) {
      _pendingVisibleLocaleAssistLocale = candidate;
      _addDebugLog(
        'VISIBLE LOCALE ASSIST ARMED -> $candidate | wait=$_noProgressCount/${TeleprompterNotifier._visibleLocaleAssistAfterWaits}',
      );
      if (_noProgressCount <
          TeleprompterNotifier._visibleLocaleAssistAfterWaits) {
        return false;
      }
    }

    if (_noProgressCount <
        TeleprompterNotifier._visibleLocaleAssistAfterWaits) {
      return false;
    }

    final now = DateTime.now();
    final lastAssistAt = _lastVisibleLocaleAssistAt;
    if (lastAssistAt != null &&
        now.difference(lastAssistAt) <
            TeleprompterNotifier._visibleLocaleAssistCooldown) {
      return false;
    }

    _lastVisibleLocaleAssistAt = now;
    _lastVisibleLocaleAssistLocale = candidate;
    _visibleLocaleAssistPinnedLocale = candidate;
    _visibleLocaleAssistPinnedUntil =
        now.add(TeleprompterNotifier._visibleLocaleAssistPinDuration);
    _pendingVisibleLocaleAssistLocale = null;
    _noProgressCount = 0;
    final switched = _switchLocaleIfNeeded(
      candidate,
      reason: 'visible skip assist',
    );
    if (switched) {
      _addDebugLog(
        'VISIBLE LOCALE ASSIST -> $candidate | window=$_visibleWordStart-$_visibleWordEnd | heard="$heard"',
      );
    }
    return switched;
  }

  String? _nextVisibleLocaleCandidate(Script script) {
    if (_sectionLocales.length != script.words.length) {
      _precomputeSectionLocales(script);
    }
    if (_sectionLocales.isEmpty || script.words.isEmpty) return null;

    final rawStart = _visibleWordStart ?? _currentState.confirmedWordIndex + 1;
    final rawEnd = _visibleWordEnd ?? rawStart;
    final start = rawStart.clamp(0, script.words.length - 1).toInt();
    final end = rawEnd.clamp(start, script.words.length - 1).toInt();
    final minIndex =
        (_currentState.confirmedWordIndex + 1).clamp(0, end).toInt();
    final scanStart = start < minIndex ? minIndex : start;
    if (scanStart > end) return null;

    final candidates = <String>[];
    String? lastSectionLocale;
    for (var i = scanStart; i <= end; i++) {
      final word = script.words[i];
      if (!TeleprompterNotifier._wordCarriesLanguage(word)) continue;
      final locale = _sectionLocales[i];
      if (locale == lastSectionLocale) continue;
      lastSectionLocale = locale;
      if (locale != _activeLocale && !candidates.contains(locale)) {
        candidates.add(locale);
      }
    }
    if (candidates.isEmpty) return null;
    if (_lastVisibleLocaleAssistLocale == null) return candidates.first;

    final lastIdx = candidates.indexOf(_lastVisibleLocaleAssistLocale!);
    if (lastIdx < 0 || candidates.length == 1) return candidates.first;
    return candidates[(lastIdx + 1) % candidates.length];
  }

  void _resetVisibleLocaleAssist() {
    _lastVisibleLocaleAssistAt = null;
    _lastVisibleLocaleAssistLocale = null;
    _visibleLocaleAssistPinnedUntil = null;
    _visibleLocaleAssistPinnedLocale = null;
    _pendingVisibleLocaleAssistLocale = null;
  }

  bool _visibleLocaleAssistPinActive({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final active = TeleprompterNotifier.shouldBlockLocaleSyncDuringAssistPin(
      pinnedLocale: _visibleLocaleAssistPinnedLocale,
      activeLocale: _activeLocale,
      scriptLocale: _scriptLanguageLocale,
      pinnedUntil: _visibleLocaleAssistPinnedUntil,
      now: clock,
    );
    if (!active) {
      _visibleLocaleAssistPinnedUntil = null;
      _visibleLocaleAssistPinnedLocale = null;
    }
    return active;
  }
}
