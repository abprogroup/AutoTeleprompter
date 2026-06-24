part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  int? _relockTargetFromTranscript(Script script, String transcript) {
    _lastRelockScope = 'none';
    if (transcript.trim().isEmpty) return null;

    final quickOnly =
        _noProgressCount < TeleprompterNotifier._stuckRelockAfterWaits;
    final windows = _recentTranscriptWindows(transcript);
    final candidates = windows.isEmpty ? <String>[transcript] : windows;
    for (var i = 0; i < candidates.length; i++) {
      final target = _relockTargetFromTranscriptWindow(
        script,
        candidates[i],
        quickOnly: quickOnly,
      );
      if (target == null) continue;
      if (i > 0) _lastRelockScope = '$_lastRelockScope-window${i + 1}';
      return target;
    }
    return null;
  }

  int? _relockTargetFromTranscriptWindow(
    Script script,
    String transcript, {
    required bool quickOnly,
  }) {
    if (_visibleWordStart == null || _visibleWordEnd == null) {
      _lastRelockScope = 'no-visible-window';
      return null;
    }

    const relockService = SttVisibleRelockService();
    final anchorTarget = relockService.anchorTarget(
      words: script.words,
      transcript: transcript,
      currentIndex: _currentState.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
    );
    if (anchorTarget != null) {
      _lastRelockScope = 'visible-anchor';
      return anchorTarget;
    }
    if (quickOnly) {
      _lastRelockScope = 'quick-visible-no-match';
      return null;
    }

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
}
