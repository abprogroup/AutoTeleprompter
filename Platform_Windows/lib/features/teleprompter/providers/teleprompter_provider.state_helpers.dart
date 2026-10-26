part of 'teleprompter_provider.dart';

extension TeleprompterNotifierStateHelpers on TeleprompterNotifier {
  void _resetTrackingForManualPosition() {
    final preserveStream =
        !_sessionStopped &&
        _lastResultUsesCumulativeTranscript &&
        _latestCumulativeTranscriptWords.isNotEmpty;
    if (preserveStream) {
      _acknowledgeTranscriptFloor(_latestCumulativeTranscriptWords.length);
      _protectManualTranscriptBoundary = true;
    }
    _resetSttTrackingContext(clearTranscriptFloor: !preserveStream);
  }

  void _acknowledgeTranscriptFloor(int spokenWordCount) {
    _transcriptFloor = spokenWordCount;
    if (!_lastResultUsesCumulativeTranscript) return;
    if (spokenWordCount >= _latestCumulativeTranscriptWords.length) {
      _browserTranscriptBoundary.consumeSnapshot();
    }
    _cumulativeTranscriptBaselineWords = List<String>.unmodifiable(
      _latestCumulativeTranscriptWords,
    );
    _cumulativeTranscriptBaselineFloor =
        spokenWordCount
            .clamp(0, _cumulativeTranscriptBaselineWords.length)
            .toInt();
  }

  void _resetStaleNoProgressTracking() {
    _lastNoProgressTranscriptKey = null;
    _staleNoProgressTranscriptCount = 0;
  }

  void _clearPendingVisibleSkipEvidence() {
    _pendingVisibleSkipTranscript = '';
    _pendingVisibleSkipOriginIndex = null;
    _pendingVisibleSkipStartIndex = null;
    _pendingVisibleSkipEndIndex = null;
    _pendingVisibleSkipStartedAt = null;
  }

  bool get _pendingVisibleSkipHasExpired =>
      TeleprompterNotifier.isPendingVisibleSkipExpired(
        startedAt: _pendingVisibleSkipStartedAt,
        now: DateTime.now(),
      );

  int _currentSttAdvanceGuardIndex(int confirmedIndex) =>
      _fluidAdvanceTimer?.isActive == true &&
              _fluidTarget > confirmedIndex &&
              _isVisibleSttTarget(_fluidTarget)
          ? _fluidTarget
          : confirmedIndex;

  // Speech owns the accepted destination; painting may still be catching up.
  // A manual/stop/visibility cancellation removes this temporary authority.
  int get _sttAcceptedIndex =>
      _currentSttAdvanceGuardIndex(_currentState.confirmedWordIndex);

  String _noProgressTranscriptKey(String transcript) {
    final words = transcript
        .split(RegExp(r'\s+'))
        .map((word) => word.trim().normalizeForMatching())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '';
    final start = words.length > 8 ? words.length - 8 : 0;
    return words.sublist(start).join(' ');
  }
}
