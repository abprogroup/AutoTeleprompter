part of 'teleprompter_provider.dart';

extension TeleprompterNotifierStalePartials on TeleprompterNotifier {
  bool _shouldIgnorePostAdvanceApplePartial(String transcript) {
    if (_useWhisper || _sttService.platformName != 'Apple') return false;
    final target = _lastSttAdvanceTargetIndex;
    final lastAt = _lastSttAdvanceAt;
    if (target == null || lastAt == null) return false;
    if (_currentState.confirmedWordIndex != target) return false;
    if (DateTime.now().difference(lastAt) >
        TeleprompterNotifier._postAdvanceStalePartialWindow) {
      return false;
    }
    final currentKey =
        TeleprompterNotifier.sttPostAdvancePartialKey(transcript);
    return TeleprompterNotifier.isStalePostAdvancePartial(
      currentKey: currentKey,
      lastAdvanceKey: _lastSttAdvanceTranscriptKey,
    );
  }

  bool _shouldHoldPostAdvanceAppleContext(String transcript, Script script) {
    if (_useWhisper || _sttService.platformName != 'Apple') return false;
    final target = _lastSttAdvanceTargetIndex;
    final lastAt = _lastSttAdvanceAt;
    if (target == null || lastAt == null) return false;
    if (_currentState.confirmedWordIndex != target) return false;
    if (DateTime.now().difference(lastAt) >
        TeleprompterNotifier._postAdvanceStalePartialWindow) {
      return false;
    }

    final transcriptWords =
        TeleprompterNotifier.sttPostAdvancePartialKey(transcript)
            .split(RegExp(r'\s+'))
            .where((word) => word.isNotEmpty)
            .toList(growable: false);
    if (transcriptWords.length < 2) return false;

    final confirmedTail = _recentConfirmedTailWords(script, target);
    if (confirmedTail.length < 2) return false;
    return _orderedOverlapCount(transcriptWords, confirmedTail) >= 2;
  }

  List<String> _recentConfirmedTailWords(Script script, int targetIndex) {
    if (script.words.isEmpty) return const [];
    final tail = <String>[];
    for (var i = targetIndex.clamp(0, script.words.length - 1).toInt();
        i >= 0 && tail.length < 4;
        i--) {
      final word = script.words[i];
      if (word.isNewline || word.normalized.isEmpty) continue;
      if (RegExp(r'^[0-9\.:\-\/]+$').hasMatch(word.normalized)) continue;
      tail.insert(0, word.normalized);
    }
    return tail;
  }

  int _orderedOverlapCount(
      List<String> transcriptWords, List<String> scriptTail) {
    var count = 0;
    var cursor = 0;
    for (final scriptWord in scriptTail) {
      while (cursor < transcriptWords.length &&
          transcriptWords[cursor] != scriptWord) {
        cursor++;
      }
      if (cursor >= transcriptWords.length) continue;
      count++;
      cursor++;
    }
    return count;
  }

  void _rememberPostAdvanceApplePartial(String transcript, int targetIndex) {
    if (_useWhisper || _sttService.platformName != 'Apple') return;
    final key = TeleprompterNotifier.sttPostAdvancePartialKey(transcript);
    if (key.isEmpty) return;
    _lastSttAdvanceTranscriptKey = key;
    _lastSttAdvanceTargetIndex = targetIndex;
    _lastSttAdvanceAt = DateTime.now();
  }

  void _resetPostAdvancePartialGuard() {
    _lastSttAdvanceTranscriptKey = null;
    _lastSttAdvanceTargetIndex = null;
    _lastSttAdvanceAt = null;
  }
}
