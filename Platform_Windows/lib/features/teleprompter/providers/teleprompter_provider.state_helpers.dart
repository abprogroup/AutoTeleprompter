part of 'teleprompter_provider.dart';

extension TeleprompterNotifierStateHelpers on TeleprompterNotifier {
  void _acknowledgeTranscriptFloor(int spokenWordCount) {
    _transcriptFloor = spokenWordCount;
    if (!_useWhisper) return;
    _cumulativeTranscriptBaselineWords = List<String>.unmodifiable(
      _latestCumulativeTranscriptWords,
    );
    _cumulativeTranscriptBaselineFloor =
        spokenWordCount
            .clamp(0, _cumulativeTranscriptBaselineWords.length)
            .toInt();
  }

  /// True after the tracker has genuinely stalled long enough to widen the
  /// visible-skip recovery window beyond the rendered viewport.
  bool get _isSustainedlyStuck {
    if (_sttEvidenceTrackingState != SttEvidenceTrackingState.recovering &&
        _sttEvidenceTrackingState != SttEvidenceTrackingState.offScript) {
      return false;
    }
    final since = _lastConfirmedAdvanceAt ?? _sessionStartTime;
    if (since == null) return false;
    return DateTime.now().difference(since) >=
        TeleprompterNotifier._sustainedStuckThreshold;
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
  }

  int _currentSttAdvanceGuardIndex(int confirmedIndex) =>
      _fluidAdvanceTimer?.isActive == true && _fluidTarget > confirmedIndex
          ? _fluidTarget
          : confirmedIndex;

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
