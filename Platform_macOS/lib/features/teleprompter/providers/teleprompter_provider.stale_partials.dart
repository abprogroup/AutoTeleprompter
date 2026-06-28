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
