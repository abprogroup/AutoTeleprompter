part of 'teleprompter_provider.dart';

extension TeleprompterNotifierLocale on TeleprompterNotifier {
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
    _resetSttTrackingContext();
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
