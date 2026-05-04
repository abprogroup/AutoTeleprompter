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
}
