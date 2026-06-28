part of 'teleprompter_provider.dart';

extension TeleprompterNotifierTranscriptRefresh on TeleprompterNotifier {
  void _refreshAppleTranscriptAfterManualBackJump({
    required int previousIndex,
    required int targetIndex,
  }) {
    if (_useWhisper || _sttService.platformName != 'Apple') return;
    if (targetIndex >= previousIndex) return;
    final now = DateTime.now();
    final last = _lastManualJumpTranscriptRefreshAt;
    if (last != null &&
        now.difference(last) <
            TeleprompterNotifier._manualBackJumpTranscriptRefreshCooldown) {
      return;
    }
    _lastManualJumpTranscriptRefreshAt = now;
    _addDebugLog(
      '[APPLE] transcript refreshed after backward position jump '
      '#$previousIndex -> #$targetIndex',
    );
    unawaited(_sttService.restart(localeId: _activeLocale).then((result) {
      if (_disposed || _sessionStopped) return;
      if (!result.success) {
        _addDebugLog(
          '[APPLE] manual-jump transcript refresh failed: ${result.message}',
        );
      }
    }));
  }
}
