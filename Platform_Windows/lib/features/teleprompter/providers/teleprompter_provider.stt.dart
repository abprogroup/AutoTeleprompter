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
          words.contains('×¢×¦×•×¨') ||
          words.contains('×¢×¦×™×¨×”')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: STOP');
        ref.read(settingsProvider.notifier).setScrollSpeed(0);
        return;
      } else if (words.contains('start prompt') || words.contains('×‘×•×')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: START');
        if (settings.scrollSpeed == 0) {
          ref.read(settingsProvider.notifier).setScrollSpeed(100);
        }
        return;
      } else if (words.contains('speed up') || words.contains('×ž×”×¨')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: FASTER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed + 25).clamp(-300, 300));
        return;
      } else if (words.contains('slow down') || words.contains('×œ××˜')) {
        _addDebugLog('ðŸ—£ï¸ VOICE COMMAND: SLOWER');
        ref
            .read(settingsProvider.notifier)
            .setScrollSpeed((settings.scrollSpeed - 25).clamp(-300, 300));
        return;
      }
    } catch (_) {}

    _accumulatedTranscript = result.words;
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

    final aligned = WordAligner.align(
      script: script.words,
      transcript: _accumulatedTranscript,
      lastConfirmedIndex: _currentState.confirmedWordIndex,
      visibleSkipStartIndex:
          maxSkipTargetIndex == null ? null : _visibleWordStart,
      maxSkipTargetIndex: maxSkipTargetIndex,
      strictBulletMode: strictBulletMode,
      policy: policy,
      readingStandby: _sttReadingStandby,
    );

    final currentIdx = _currentState.confirmedWordIndex;
    final nextExpected = (currentIdx + 1 < script.words.length)
        ? script.words
            .skip(currentIdx + 1)
            .where((w) => !w.isNewline)
            .take(3)
            .map((w) => w.raw)
            .join(' ')
        : '<END>';

    final engineTag = _useWhisper ? 'ðŸ¤–' : 'ðŸŽ¤';
    if (aligned.shouldEnterStandby) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      _addDebugLog(
          '$engineTag STANDBY LOCK | ${aligned.debugInfo} | heard: "${result.words}"');
      LightweightDiagnostics.instance.record(
        'stt',
        'standby lock',
        data: {
          'heard': result.words,
          'position': _currentState.confirmedWordIndex,
          'confidence': aligned.confidence,
        },
      );
      return;
    }

    if (aligned.shouldAdvance &&
        aligned.confirmedWordIndex > _currentState.confirmedWordIndex) {
      _sttReadingStandby = true;
      _noProgressCount = 0;
      _resetVisibleLocaleAssist();
      final visibleSkipTargetTrusted =
          TeleprompterNotifier.isTrustedVisibleSkipTarget(
        alignedIndex: aligned.confirmedWordIndex,
        visibleWordStart: _visibleWordStart,
        visibleWordEnd: _visibleWordEnd,
      );
      final target = TeleprompterNotifier.resolveAdvanceTarget(
        currentIndex: _currentState.confirmedWordIndex,
        alignedIndex: aligned.confirmedWordIndex,
        visibleMaxSkipTargetIndex:
            visibleSkipTargetTrusted ? maxSkipTargetIndex : null,
      );
      final advancedWord =
          target < script.words.length ? script.words[target].raw : '?';
      _addDebugLog(
          '$engineTag âœ… ADVANCE â†’ #$target "$advancedWord" (conf=${aligned.confidence.toStringAsFixed(2)}) | heard: "${result.words}"');
      LightweightDiagnostics.instance.record(
        'stt',
        'advanced',
        data: {
          'from': _currentState.confirmedWordIndex,
          'to': target,
          'word': advancedWord,
          'confidence': aligned.confidence,
          'heard': result.words,
        },
      );

      // Fluid advancement: if jumping more than 3 words, animate
      // through intermediate words so the user's eye can follow.
      final jump = target - _currentState.confirmedWordIndex;
      if (visibleSkipTargetTrusted || jump <= 3) {
        // Small jumps and trusted visible-skip targets are instant.
        _fluidAdvanceTimer?.cancel();
        _safeSetState((s) => s.copyWith(confirmedWordIndex: target));
      } else {
        // Large jump â€” advance word by word with short delays
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
            '$engineTag IMPROVISING | heard: "${result.words}" | visible relock waiting');
        LightweightDiagnostics.instance.record(
          'stt',
          'improvising',
          data: {'heard': result.words, 'position': currentIdx},
        );
      } else {
        _addDebugLog(
            '$engineTag WAIT #$_noProgressCount | heard: "${result.words}" | next: "$nextExpected"');
        LightweightDiagnostics.instance.record(
          'stt',
          'waiting',
          data: {
            'heard': result.words,
            'next': nextExpected,
            'position': currentIdx,
            'stuckCount': _noProgressCount,
          },
        );
        _checkAndSwitchLocale();
      }

      if (_maybeAssistVisibleLocale(script, policy, result.words)) {
        return;
      }
    }
  }

  void _setupSttCallbacks() {
    final platform = _sttService.platformName;

    _sttService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _sttService.onSoundLevelChange = (level) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Push live level to UI _currentState.
      _safeSetState((s) => s.copyWith(soundLevel: level.clamp(0.0, 1.0)));
      _lastVolLog = DateTime.now();
    };

    _sttService.onDiagnostic = (msg) {
      if (_disposed) return;
      _addDebugLog(msg);
    };

    _sttService.onAudioInputDevicesChanged = (devices) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _safeSetState((s) => s.copyWith(audioInputDevices: devices));

      final selectedId = ref.read(settingsProvider).sttInputDeviceId;
      if (selectedId.isEmpty) return;
      for (final device in devices) {
        if (device.id == selectedId) {
          final currentLabel = ref.read(settingsProvider).sttInputDeviceLabel;
          if (device.label.isNotEmpty && device.label != currentLabel) {
            ref
                .read(settingsProvider.notifier)
                .setSttInputDevice(device.id, device.label);
          }
          return;
        }
      }
      _addDebugLog(
          'ðŸŽ™ï¸ Selected microphone was not found; using system default input.');
    };

    _sttService.onStatusChange = (status) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      // Ignore non-listening statuses during the start-up guard window.
      // This prevents stale async 'notListening' from the previous stop()
      // from resetting isListening=false right after the new session starts.
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('ðŸŽ¤ [${_sttService.platformName}] STATUS: $status');
      LightweightDiagnostics.instance.record(
        'stt',
        'status changed',
        data: {'platform': _sttService.platformName, 'status': '$status'},
      );
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('ðŸŽ¤ [${_sttService.platformName}] STT ERROR: $error');
      LightweightDiagnostics.instance.record(
        'stt',
        'STT error',
        data: {'platform': _sttService.platformName, 'error': error},
      );
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available');
      _safeSetState((s) => s.copyWith(
            statusMessage: isFatal ? error : '',
            hasError: isFatal,
            isListening: isFatal ? false : s.isListening,
            isStarting: isFatal ? false : s.isStarting,
          ));
    };

    _sttService.onLanguageUnavailable = (requestedLocale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(
        _scriptLanguageLocale ?? requestedLocale,
      );
      _addDebugLog('ðŸŽ¤ [$platform] LANGUAGE UNAVAILABLE: $langName');
      _safeSetState((s) => s.copyWith(
            missingLanguage: langName,
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                'Speech recognition language not installed on this device',
          ));
    };

    // Android-only: fires when offline + cloud STT both fail for a language.
    // On Apple/Windows this callback is never invoked.
    _sttService.onNeedLanguagePack = (locale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(locale);
      _addDebugLog(
          'ðŸŽ¤ [$platform] ALL STT FAILED for $langName â€” internet required');
      _safeSetState((s) => s.copyWith(
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                '$langName speech recognition requires an internet connection. '
                'This language is not available offline on your device. '
                'Please connect to WiFi or mobile data and try again.',
          ));
    };
  }

  void _setupWhisperCallbacks() {
    _whisperService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _whisperService.onStatusChange = (status) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('ðŸ¤– WHISPER STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _whisperService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      _addDebugLog('ðŸ¤– WHISPER ERROR: $error');
      final isFatal =
          error.contains('not available') || error.contains('init failed');
      if (isFatal) {
        _safeSetState((s) => s.copyWith(
              statusMessage: error,
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
      }
    };
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

  /// Current v5 metadata safely resolves Hebrew/RTL and English/LTR only.
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
