part of 'teleprompter_provider.dart';

/// Manual navigation owns the reading position, not microphone lifetime.
extension TeleprompterManualScroll on TeleprompterNotifier {
  bool get manualScrollInProgress => _manualScrollInProgress;

  bool beginManualScroll() {
    if (_disposed ||
        _sessionStopped ||
        _currentScript == null ||
        (!_currentState.isListening && !_currentState.isStarting)) {
      return false;
    }
    if (_manualScrollInProgress) return true;
    _manualScrollInProgress = true;
    _fluidAdvanceTimer?.cancel();
    _resetTrackingForManualPosition();
    LightweightDiagnostics.instance.record(
      'position',
      'manual navigation started',
      data: {'position': _currentState.confirmedWordIndex},
    );
    return true;
  }

  void finishManualScroll(int index, {required Script script}) {
    if (!_manualScrollInProgress) return;
    _manualScrollInProgress = false;
    if (_disposed ||
        _sessionStopped ||
        _currentScript == null ||
        script.sessionId != _currentScript!.sessionId) {
      return;
    }
    // Even a gesture returning to the same word must settle its consumed
    // transcript. The widget suppresses visual auto-follow during this commit.
    jumpToPosition(index, script: script);
    LightweightDiagnostics.instance.record(
      'position',
      'manual navigation settled',
      data: {'position': _currentState.confirmedWordIndex},
    );
  }

  void cancelManualScroll() {
    if (!_manualScrollInProgress) return;
    _manualScrollInProgress = false;
    if (!_disposed && !_sessionStopped) _resetTrackingForManualPosition();
  }

  bool _consumeSpeechDuringManualScroll(SpeechResult result) {
    if (!_manualScrollInProgress) return false;
    _sttResultFlow.record(filtered: true, now: DateTime.now());
    if (result.isCumulative) {
      // Preserve provenance using the PRIMARY snapshot only, without running
      // matching, voice commands or locale assistance against a moving viewport.
      final words =
          const SttTranscriptBufferService()
              .update(rawTranscript: result.words, transcriptFloor: 0)
              .spokenWords;
      final previous = _cumulativeTranscriptBaselineWords;
      final stableAppend =
          words.length >= previous.length &&
          Iterable<int>.generate(
            previous.length,
          ).every((i) => previous[i] == words[i]);
      // Empty/retracted interim snapshots are not new speech. Retain the
      // consumed high-water snapshot so regrowth cannot reopen its suffix.
      // Settled final corrections keep the existing manual-jump rebase rule.
      if (words.isNotEmpty && (stableAppend || result.isFinal)) {
        _latestCumulativeTranscriptWords = words;
        _acknowledgeTranscriptFloor(words.length);
        _protectManualTranscriptBoundary = true;
      }
    }
    return true;
  }
}
