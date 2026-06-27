part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  int? _relockTargetFromTranscript(
    Script script,
    String transcript,
    SttRecognitionPolicy policy,
  ) {
    _lastRelockScope = 'none';
    if (transcript.trim().isEmpty) return null;
    if (!policy.visibleSkipEnabled) {
      _lastRelockScope = 'visible-skip-off';
      return null;
    }

    final quickOnly =
        _noProgressCount < TeleprompterNotifier._stuckRelockAfterWaits;
    final windows = _recentTranscriptWindows(transcript);
    final candidates = windows.isEmpty ? <String>[transcript] : windows;
    for (var i = 0; i < candidates.length; i++) {
      final target = _relockTargetFromTranscriptWindow(
        script,
        candidates[i],
        policy: policy,
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
    required SttRecognitionPolicy policy,
    required bool quickOnly,
  }) {
    if (_visibleWordStart == null || _visibleWordEnd == null) {
      _lastRelockScope = 'no-visible-window';
      return null;
    }

    const relockService = SttVisibleRelockService();
    if (quickOnly) {
      _lastRelockScope = 'quick-visible-no-match';
      return null;
    }

    final exactTarget = relockService.exactPhraseTarget(
      words: script.words,
      transcript: transcript,
      currentIndex: _currentState.confirmedWordIndex,
      visibleWordStart: _visibleWordStart,
      visibleWordEnd: _visibleWordEnd,
      minWords: policy.visibleSkip.smallWords.clamp(3, 8).toInt(),
    );
    if (exactTarget != null) {
      _lastRelockScope = 'visible-exact';
      return exactTarget;
    }

    _lastRelockScope = 'visible-only-no-match';
    return null;
  }
}
