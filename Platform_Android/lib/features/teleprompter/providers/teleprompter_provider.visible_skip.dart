// This part extends TeleprompterNotifier inside the same library so the main
// provider can stay under the surgical line-count limit without changing
// runtime ownership. Riverpod marks `state` as protected even for same-library
// extension parts, so the warning is suppressed here only.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'teleprompter_provider.dart';

extension TeleprompterVisibleSkipAssist on TeleprompterNotifier {
  bool _maybeAssistVisibleLocale(
    Script script,
    AppSettings settings,
    String heard,
  ) {
    if (_disposed || _sessionStopped) return false;
    if (!settings.sttVisibleSkipEnabled || heard.trim().isEmpty) return false;
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
          currentIndex: state.confirmedWordIndex,
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

    final rawStart = _visibleWordStart ?? state.confirmedWordIndex + 1;
    final rawEnd = _visibleWordEnd ?? rawStart;
    final start = rawStart.clamp(0, script.words.length - 1).toInt();
    final end = rawEnd.clamp(start, script.words.length - 1).toInt();
    final minIndex = (state.confirmedWordIndex + 1).clamp(0, end).toInt();
    final scanStart = start < minIndex ? minIndex : start;
    if (scanStart > end) return null;

    final candidates = <String>[];
    String? lastSectionLocale;
    for (var i = scanStart; i <= end; i++) {
      final word = script.words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
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

  /// Pre-compute a per-word locale map so mixed Hebrew/English scripts can
  /// switch languages before the boundary, matching the tested iOS behavior.
  void _precomputeSectionLocales(Script script) {
    const minSectionWords = 3;

    final realWords = script.words
        .where((w) => !w.isNewline && w.normalized.isNotEmpty)
        .toList();
    if (realWords.isEmpty) {
      _sectionLocales = const [];
      return;
    }

    final raw = realWords.map((w) => w.isRtl ? 'he_IL' : 'en_US').toList();
    final smoothed = List<String>.from(raw);
    var changed = true;
    while (changed) {
      changed = false;
      var i = 0;
      while (i < smoothed.length) {
        final locale = smoothed[i];
        final runStart = i;
        while (i < smoothed.length && smoothed[i] == locale) {
          i++;
        }
        final runLen = i - runStart;
        if (runLen < minSectionWords) {
          final inherit = runStart > 0
              ? smoothed[runStart - 1]
              : (i < smoothed.length ? smoothed[i] : locale);
          if (inherit != locale) {
            for (var j = runStart; j < i; j++) {
              smoothed[j] = inherit;
            }
            changed = true;
          }
        }
      }
    }

    final mapped = <String>[];
    var realIndex = 0;
    for (final word in script.words) {
      if (word.isNewline || word.normalized.isEmpty) {
        mapped.add(mapped.isNotEmpty ? mapped.last : smoothed.first);
      } else {
        mapped.add(realIndex < smoothed.length ? smoothed[realIndex] : 'en_US');
        realIndex++;
      }
    }
    _sectionLocales = mapped;
  }

  int _effectiveSkipThreshold() {
    if (_sectionLocales.isEmpty)
      return TeleprompterNotifier._googleSkipAfterStuck;
    final currentIdx = state.confirmedWordIndex;
    for (var lookahead = 1; lookahead <= 2; lookahead++) {
      final checkIdx = currentIdx + lookahead;
      if (checkIdx < _sectionLocales.length &&
          _sectionLocales[checkIdx] != _activeLocale) {
        return 5;
      }
    }
    return TeleprompterNotifier._googleSkipAfterStuck;
  }

  void _checkAndSwitchLocale() {
    if (_disposed || _sessionStopped) return;
    if (_visibleLocaleAssistPinActive()) return;
    if (_sectionLocales.isEmpty) return;
    final currentIdx = state.confirmedWordIndex;
    if (currentIdx < 0 || currentIdx >= _sectionLocales.length) return;
    final lookIdx =
        (currentIdx + 1).clamp(0, _sectionLocales.length - 1).toInt();
    final needed = _sectionLocales[lookIdx];
    _switchLocaleIfNeeded(needed, reason: 'pre-switch');
  }

  void _syncLocaleForPosition(Script script, int wordIndex,
      {required String reason}) {
    if (_sessionStopped || _disposed) return;
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
    if (_disposed || _sessionStopped) return false;
    if (locale == _activeLocale && locale == _scriptLanguageLocale) {
      return false;
    }
    final previous = _activeLocale ?? _scriptLanguageLocale ?? '?';
    _activeLocale = locale;
    _scriptLanguageLocale = locale;
    _accumulatedTranscript = '';
    final engineName = _sttService.platformName.toUpperCase();
    _addDebugLog('STT LOCALE [$engineName]: $previous -> $locale ($reason)');
    _safeSetState((s) => s.copyWith(isStarting: true, soundLevel: 0.0));
    _sttService.setLocale(locale);
    return true;
  }

  /// Find the next non-newline word index after [from]
  int? _nextRealWord(int from, Script script) {
    for (int i = from + 1; i < script.words.length; i++) {
      if (!script.words[i].isNewline && script.words[i].normalized.isNotEmpty) {
        return i;
      }
    }
    return null;
  }
}
