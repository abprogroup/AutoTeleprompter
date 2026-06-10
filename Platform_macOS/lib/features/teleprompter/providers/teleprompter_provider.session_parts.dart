part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSessionParts on TeleprompterNotifier {
  List<String> _recentTranscriptWindows(String transcript) =>
      TeleprompterNotifier.liveTranscriptWindowsForAlignment(transcript);


  int? _relockTargetFromTranscript(Script script, String transcript) {
    _lastRelockScope = 'none';
    if (_noProgressCount < TeleprompterNotifier._stuckRelockAfterWaits) {
      return null;
    }
    if (transcript.trim().isEmpty) return null;

    final windows = _recentTranscriptWindows(transcript);
    final candidates = windows.isEmpty ? <String>[transcript] : windows;
    for (var i = 0; i < candidates.length; i++) {
      final target = _relockTargetFromTranscriptWindow(
        script,
        candidates[i],
      );
      if (target == null) continue;
      if (i > 0) _lastRelockScope = '$_lastRelockScope-window${i + 1}';
      return target;
    }
    return null;
  }

  int? _relockTargetFromTranscriptWindow(Script script, String transcript) {
    if (_visibleWordStart == null || _visibleWordEnd == null) {
      _lastRelockScope = 'no-visible-window';
      return null;
    }

    const relockService = SttVisibleRelockService();
    final fuzzyTarget = relockService.fuzzyTarget(
      words: script.words,
      transcript: transcript,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    if (fuzzyTarget != null) {
      _lastRelockScope = 'visible-fuzzy';
      return fuzzyTarget;
    }

    final visibleApproximateTarget = relockService.approximateTarget(
      words: script.words,
      transcript: transcript,
      currentIndex: _currentState.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
      minimumScore: _noProgressCount >=
              TeleprompterNotifier._relaxedVisibleRelockAfterWaits
          ? 0.76
          : 0.88,
    );
    if (visibleApproximateTarget != null) {
      _lastRelockScope = 'visible-approximate';
      return visibleApproximateTarget;
    }

    _lastRelockScope = 'visible-only-no-match';
    return null;
  }

  _SequentialSttProgress? _consumeSequentialSttStreak({
    required Script script,
    required String transcript,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
  }) {
    final rawTokens = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final tokens = rawTokens.length > 12
        ? rawTokens.sublist(rawTokens.length - 12)
        : rawTokens;
    if (tokens.isEmpty || script.words.isEmpty) {
      _resetSequentialSttStreak();
      return null;
    }

    final currentIndex = _currentState.confirmedWordIndex;
    if (_sequentialSttBaseIndex != currentIndex &&
        _sequentialSttEndIndex != currentIndex) {
      _resetSequentialSttStreak();
    }

    _sequentialSttBaseIndex ??= currentIndex;
    _sequentialSttEndIndex ??= currentIndex;
    var probeIndex = _sequentialSttEndIndex!;
    var evidence = _sequentialSttEvidence;
    var matched = 0;
    var duplicateIgnored = 0;
    var consumedPrefixIgnored = 0;
    final now = DateTime.now();

    for (final token in tokens) {
      final nextIndex = WordAligner.nextSpeakableIndex(
        script.words,
        probeIndex + 1,
      );
      if (nextIndex >= script.words.length) break;
      final nextWord = script.words[nextIndex];
      if (WordAligner.spokenWordMatchesNext(
        token,
        nextWord,
        strictBulletMode: strictBulletMode,
      )) {
        probeIndex = nextIndex;
        evidence += policy.startAdvance.evidenceCost(nextWord.normalized);
        matched++;
        _sequentialSttLastToken = token;
        _sequentialSttLastTokenAt = now;
        continue;
      }

      final baseIndex = _sequentialSttBaseIndex!;
      final endIndex = _sequentialSttEndIndex!;
      var matchedConsumedPrefix = false;
      for (var i = baseIndex + 1; i <= endIndex; i++) {
        if (i < 0 || i >= script.words.length) continue;
        if (WordAligner.spokenWordMatchesNext(
          token,
          script.words[i],
          strictBulletMode: strictBulletMode,
        )) {
          matchedConsumedPrefix = true;
          break;
        }
      }
      if (matchedConsumedPrefix) {
        consumedPrefixIgnored++;
        continue;
      }

      final lastTokenAt = _sequentialSttLastTokenAt;
      final repeatedRecentToken = _sequentialSttLastToken == token &&
          lastTokenAt != null &&
          now.difference(lastTokenAt) < const Duration(milliseconds: 1400);
      if (repeatedRecentToken) {
        duplicateIgnored++;
        continue;
      }

      _resetSequentialSttStreak();
      return null;
    }

    if (matched == 0) {
      return duplicateIgnored > 0 || consumedPrefixIgnored > 0
          ? const _SequentialSttProgress(
              null,
              'repeated token ignored; streak waiting',
            )
          : null;
    }

    _sequentialSttEndIndex = probeIndex;
    _sequentialSttEvidence = evidence;
    final threshold = policy.startAdvance;
    final needed = threshold.smallWords.toDouble();
    final reachedThreshold = evidence >= needed;
    if (!_sequentialSttUnlocked && !reachedThreshold) {
      return _SequentialSttProgress(
        null,
        'matched=$matched ignored=${duplicateIgnored + consumedPrefixIgnored} evidence=${evidence.toStringAsFixed(1)}/${needed.toStringAsFixed(1)} end=$probeIndex',
      );
    }

    _sequentialSttUnlocked = true;
    _sequentialSttBaseIndex = probeIndex;
    _sequentialSttEndIndex = probeIndex;
    _sequentialSttEvidence = 0.0;
    return _SequentialSttProgress(
      probeIndex,
      'matched=$matched ignored=${duplicateIgnored + consumedPrefixIgnored} evidence=${evidence.toStringAsFixed(1)}/${needed.toStringAsFixed(1)}',
    );
  }

  void _resetSequentialSttStreak() {
    _sequentialSttBaseIndex = null;
    _sequentialSttEndIndex = null;
    _sequentialSttEvidence = 0.0;
    _sequentialSttUnlocked = false;
    _sequentialSttLastToken = null;
    _sequentialSttLastTokenAt = null;
  }

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

  String? _visibleWindowStartLocale(Script script, int? start, int? end) {
    if (start == null || end == null || script.words.isEmpty) return null;
    final windowStart = start.clamp(0, script.words.length - 1).toInt();
    final windowEnd = end.clamp(windowStart, script.words.length - 1).toInt();
    for (var i = windowStart; i <= windowEnd; i++) {
      final locale = TeleprompterNotifier._strongLocaleForWord(script.words[i]);
      if (locale != null) return locale;
    }
    return null;
  }

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
    _resetSequentialSttStreak();
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

  Future<void> startSession(Script script) async {
    final pendingStop = _stopInFlight;
    if (pendingStop != null) await pendingStop;
    if (_disposed) return;

    final token = ++_sessionToken;
    final sameScript = _currentScript != null &&
        _currentScript!.sessionId.isNotEmpty &&
        _currentScript!.sessionId == script.sessionId;
    _currentScript = script;
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _resetSequentialSttStreak();
    _sessionStopped = false;
    _sessionStartTime = DateTime.now();
    _silentWarningFired = false;
    _lastVolLog = null;
    final startupVisibleStart = _visibleWordStart;
    final startupVisibleEnd = _visibleWordEnd;
    _resetVisibleLocaleAssist();
    _precomputeSectionLocales(script);
    final settings = ref.read(settingsProvider);
    final sttEngine = settings.sttEngine;
    _useWhisper = sttEngine.startsWith('whisper');
    final resumeIndex = sameScript ? _currentState.confirmedWordIndex : 0;
    final startIndex = resumeIndex.clamp(
      0,
      script.words.isEmpty ? 0 : script.words.length - 1,
    );
    _writeState((s) => s.copyWith(
        confirmedWordIndex: startIndex,
        isListening: false,
        isStarting: true,
        hasError: false,
        statusMessage: '',
        debugLogs: [],
        missingLanguage: null));

    _addDebugLog(
        'SESSION START | ${script.words.where((w) => !w.isNewline).length} words | pos=$startIndex');
    final visibleLocale = _visibleWindowStartLocale(
        script, startupVisibleStart, startupVisibleEnd);
    final localeId = visibleLocale ??
        TeleprompterNotifier.resolveInitialSttLocaleForSettings(
          script.words,
          settings,
          startIndex: startIndex,
          sectionLocales: _sectionLocales,
        );
    _scriptLanguageLocale = localeId;
    _activeLocale = localeId;
    if (visibleLocale != null) {
      _visibleLocaleAssistPinnedLocale = localeId;
      _visibleLocaleAssistPinnedUntil = DateTime.now()
          .add(TeleprompterNotifier._visibleLocaleAssistPinDuration);
      _addDebugLog(
          'STT START VISIBLE LOCALE: $localeId | window=$startupVisibleStart-$startupVisibleEnd');
    }

    if (script.words.isNotEmpty) {
      final initialLocale = localeId;
      final realWords =
          script.words.where(TeleprompterNotifier._wordCarriesLanguage).toList();
      final hebrewCount = realWords
          .where((w) => TeleprompterNotifier._explicitLocaleForWord(w) == 'he_IL')
          .length;
      final ratio = realWords.isEmpty ? 0.0 : hebrewCount / realWords.length;
      _addDebugLog(
          'LANG: ${initialLocale == "he_IL" ? "Hebrew" : "English"} start (${(ratio * 100).round()}% Hebrew language words)');
      _addDebugLog(
          'STT START LOCALE: $localeId | sections=${_sectionLocales.toSet().length}');
    }

    // Start heartbeat timer in debug mode
    _heartbeatTimer?.cancel();
    if (settings.debugMode) {
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_disposed) return;
        final engineName =
            _useWhisper ? 'WHISPER' : _sttService.platformName.toUpperCase();
        final listening =
            _useWhisper ? _whisperService.isListening : _sttService.isListening;
        final pos = _currentState.confirmedWordIndex;
        final total = script.words.where((w) => !w.isNewline).length;
        _addDebugLog(
            'HEARTBEAT: $engineName ${listening ? "LISTENING" : "IDLE"} | pos=$pos/$total | stuck=$_noProgressCount');

        // Silent-listening detector: STT says listening but no audio level or results received.
        if (!_useWhisper &&
            _sttService.platformName != 'Apple' &&
            listening &&
            !_silentWarningFired &&
            _lastVolLog == null &&
            _sessionStartTime != null) {
          final elapsed = DateTime.now().difference(_sessionStartTime!);
          if (elapsed.inSeconds >= 10) {
            _silentWarningFired = true;
            _addDebugLog(
                'SILENT LISTENING: engine is active but receiving NO audio for ${elapsed.inSeconds}s.');
            _addDebugLog(
                'FIX: Ensure "Online Speech Recognition" is ON in Privacy Settings or install the Hebrew Offline Pack.');
            _safeSetState((s) => s.copyWith(
                  statusMessage:
                      'Microphone signal weak or blocked.\n1. Check Privacy Settings -> Microphone.\n2. Ensure "Online Speech Recognition" is enabled.',
                  hasError: true,
                ));
          }
        }

        // Dynamic language switching for mixed Hebrew/English scripts.
        if (!_useWhisper && listening && _currentScript != null) {
          _syncLocaleForPosition(
              _currentScript!, _currentState.confirmedWordIndex + 1,
              reason: 'heartbeat');
        }
      });
    }

    if (_useWhisper) {
      final model = whisperModelFromEngine(sttEngine);
      _addDebugLog('Starting Whisper STT ($sttEngine) offline...');
      await _whisperService.start(localeId: localeId, model: model);
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _whisperService.stop();
        return;
      }
    } else {
      final platform = _sttService.platformName;
      final selectedMicId = settings.sttInputDeviceId.trim();
      final selectedMicLabel = settings.sttInputDeviceLabel.trim();
      _sttService.setAudioInputDevice(
        selectedMicId.isEmpty ? null : selectedMicId,
        label: selectedMicLabel.isEmpty
            ? 'System default microphone'
            : selectedMicLabel,
      );
      _addDebugLog('[$platform] Starting STT locale=$localeId...');
      _addDebugLog(selectedMicId.isEmpty
          ? '[$platform] Microphone: system default input'
          : '[$platform] Microphone: $selectedMicLabel');
      final SpeechStartResult result;
      try {
        result = await _sttService.start(localeId: localeId).timeout(
              const Duration(seconds: 8),
              onTimeout: () => SpeechStartResult(
                success: false,
                message:
                    'Speech recognition did not start. Please check macOS Microphone and Speech Recognition permissions, then try again.',
              ),
            );
      } catch (error) {
        _addDebugLog('[$platform] STT START EXCEPTION: $error');
        _safeSetState((s) => s.copyWith(
              statusMessage:
                  'Speech recognition could not start. Please check macOS Microphone and Speech Recognition permissions, then try again.',
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
        return;
      }
      if (_disposed || _sessionStopped || token != _sessionToken) {
        await _sttService.stop();
        return;
      }

      if (!result.success) {
        _addDebugLog('[$platform] STT FAILED: ${result.message}');
        _safeSetState((s) => s.copyWith(
              statusMessage: result.message ?? 'Speech recognition failed',
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
        return;
      }

      // Apple platforms (iOS/macOS) fire onStatusChange asynchronously,
      // so we set isListening=true immediately here to avoid the mic button
      // staying yellow while waiting for the callback.
      if (_sttService.requiresImmediateListeningFlag) {
        _startingSession = true;
        _safeSetState((s) => s.copyWith(isListening: true, isStarting: false));
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (token == _sessionToken) _startingSession = false;
        });
      }

      if (result.languageMissing && result.missingLanguageName != null) {
        _addDebugLog(
            '[$platform] LANG MISSING: ${result.missingLanguageName} - using ${result.actualLocale}');
        _safeSetState(
            (s) => s.copyWith(missingLanguage: result.missingLanguageName));
      } else {
        _addDebugLog('[$platform] STT using locale: ${result.actualLocale}');
      }
    }
  }

  Future<void> stopSession() async {
    if (_stopInFlight != null) {
      await _stopInFlight;
      return;
    }
    _sessionToken++;
    _sessionStopped = true;
    _startingSession = false;
    _heartbeatTimer?.cancel();
    _fluidAdvanceTimer?.cancel();
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _resetSequentialSttStreak();
    _lastVolLog = null;
    _scriptLanguageLocale = null;
    _activeLocale = null;
    _sectionLocales = [];
    _visibleWordStart = null;
    _visibleWordEnd = null;
    _resetVisibleLocaleAssist();

    // Stop all engines - Whisper may have been auto-started via fallback.
    final stopFuture = Future.wait([
      _sttService.stop(),
      _whisperService.stop(),
    ]);
    _stopInFlight = stopFuture.then((_) {});
    try {
      await _stopInFlight;
    } finally {
      _stopInFlight = null;
    }

    if (!_disposed) {
      _writeState((s) => s.copyWith(
            isListening: false,
            isStarting: false,
            hasError: false,
            statusMessage: '',
            soundLevel: 0.0,
          ));
    }
  }

  void resetPosition() {
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _resetSequentialSttStreak();
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog('POSITION RESET -> 0');
    _writeState((s) => s.copyWith(confirmedWordIndex: 0));
    if (!_sessionStopped &&
        _currentScript != null &&
        _currentState.isListening) {
      _syncLocaleForPosition(_currentScript!, 0, reason: 'reset');
    }
  }

  void jumpToPosition(int index, {Script? script}) {
    if (script != null) _currentScript = script;
    final activeScript = _currentScript;
    if (_disposed || activeScript == null || activeScript.words.isEmpty) return;
    final target = index.clamp(0, activeScript.words.length - 1);
    _accumulatedTranscript = '';
    _noProgressCount = 0;
    _sttReadingStandby = false;
    _resetSequentialSttStreak();
    _resetVisibleLocaleAssist();
    _fluidAdvanceTimer?.cancel();
    _addDebugLog(
        'POSITION JUMP -> #$target "${activeScript.words[target].raw}"');
    _writeState((s) => s.copyWith(confirmedWordIndex: target));
    if (!_sessionStopped && _currentState.isListening) {
      _syncLocaleForPosition(activeScript, target, reason: 'manual jump');
    }
  }

  Future<void> refreshAudioInputDevices() async {
    final devices = await _sttService.refreshAudioInputDevices();
    if (!_disposed) {
      _writeState((s) => s.copyWith(audioInputDevices: devices));
    }
  }

  void setSttInputDevice(String deviceId, String label) {
    final normalizedId = deviceId.trim();
    final normalizedLabel =
        label.trim().isEmpty ? 'System default microphone' : label.trim();
    _sttService.setAudioInputDevice(
      normalizedId.isEmpty ? null : normalizedId,
      label: normalizedLabel,
    );
    unawaited(refreshAudioInputDevices());
    _addDebugLog(normalizedId.isEmpty
        ? 'Microphone input set to system default'
        : 'Microphone input set to $normalizedLabel');
  }

  void setVisibleWordWindow(int? startIndex, int? endIndex) {
    if (_disposed) return;
    if (startIndex != _visibleWordStart || endIndex != _visibleWordEnd) {
      _resetVisibleLocaleAssist();
    }
    _visibleWordStart = startIndex;
    _visibleWordEnd = endIndex;
  }
}
