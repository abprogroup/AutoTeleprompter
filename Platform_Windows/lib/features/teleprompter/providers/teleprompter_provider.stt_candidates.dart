part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttCandidates on TeleprompterNotifier {
  void _prepareTranscriptStream({
    required bool usesCumulativeTranscript,
    required int? browserStreamId,
  }) {
    _lastResultUsesCumulativeTranscript = usesCumulativeTranscript;
    if (_useWhisper) return;
    if (!usesCumulativeTranscript) {
      _activeBrowserCumulativeStreamId = null;
      return;
    }
    if (_activeBrowserCumulativeStreamId == browserStreamId) return;
    _activeBrowserCumulativeStreamId = browserStreamId;
    _transcriptFloor = 0;
    _cumulativeTranscriptBaselineFloor = 0;
    _cumulativeTranscriptBaselineWords = const <String>[];
    _latestCumulativeTranscriptWords = const <String>[];
  }

  _SttResultCandidate? _selectRecognitionCandidate({
    required SpeechResult result,
    required Script script,
    required SttRecognitionPolicy policy,
    required bool strictBulletMode,
    required int? maxSkipTargetIndex,
    required bool usesCumulativeTranscript,
  }) {
    final candidates = <String>[];
    for (final rawCandidate in <String>[result.words, ...result.alternatives]) {
      final candidate = rawCandidate.trim();
      if (candidate.isEmpty || candidates.contains(candidate)) continue;
      candidates.add(candidate);
      if (candidates.length >= 5) break;
    }

    _SttResultCandidate? selected;
    for (final candidate in candidates) {
      final buffer = TeleprompterNotifierStt._transcriptBuffer.update(
        rawTranscript: candidate,
        transcriptFloor:
            usesCumulativeTranscript
                ? _cumulativeTranscriptBaselineFloor
                : _transcriptFloor,
        recentWordWindow: TeleprompterNotifier._sttLiveAlignmentWindowWords,
        cumulativeReplacement: usesCumulativeTranscript,
        cumulativeBaselineWords: _cumulativeTranscriptBaselineWords,
        cumulativeFinal: usesCumulativeTranscript && result.isFinal,
      );
      if (!buffer.hasFreshSpeech) continue;
      final transcript = buffer.recentSurfaceTranscript;
      final alignment = _bestAlignmentForTranscript(
        script: script,
        transcript: transcript,
        policy: policy,
        strictBulletMode: strictBulletMode,
        maxSkipTargetIndex: maxSkipTargetIndex,
      );
      final candidateResult = _SttResultCandidate(
        buffer: buffer,
        transcript: transcript,
        alignment: alignment,
      );
      if (selected == null ||
          _recognitionCandidateIsBetter(candidateResult, selected)) {
        selected = candidateResult;
      }
    }
    return selected;
  }

  bool _recognitionCandidateIsBetter(
    _SttResultCandidate candidate,
    _SttResultCandidate current,
  ) {
    if (_alignmentIsBetter(candidate.alignment, current.alignment)) return true;
    if (_alignmentIsBetter(current.alignment, candidate.alignment)) {
      return false;
    }
    final candidateRank = _recognitionCandidateRank(candidate.alignment);
    final currentRank = _recognitionCandidateRank(current.alignment);
    if (candidateRank != currentRank) return candidateRank > currentRank;
    final evidence = candidate.alignment.evidenceWords.length.compareTo(
      current.alignment.evidenceWords.length,
    );
    if (evidence != 0) return evidence > 0;
    return candidate.alignment.confidence > current.alignment.confidence + 0.05;
  }

  int _recognitionCandidateRank(AlignmentResult alignment) {
    if (alignment.shouldAdvance) return 3;
    if (alignment.shouldEnterStandby) return 2;
    return alignment.kind == SttAlignmentKind.unknown ? 0 : 1;
  }
}

class _SttResultCandidate {
  final SttTranscriptBuffer buffer;
  final String transcript;
  final AlignmentResult alignment;

  const _SttResultCandidate({
    required this.buffer,
    required this.transcript,
    required this.alignment,
  });
}
