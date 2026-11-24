part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  List<String> _recentTranscriptWindows(String transcript) =>
      TeleprompterNotifier.liveTranscriptWindowsForAlignment(transcript);

  AbstractSttService _activeAudioInputService() {
    final engine = AppSettings.normalizeSttEngine(
      ref.read(settingsProvider).sttEngine,
    );
    if (AppSettings.isOfflineSherpaEngine(engine)) {
      _offlineSherpaSttService.configureEngine(engine);
      return _offlineSherpaSttService;
    }
    return _browserSttService;
  }

  AbstractSttService _resolveWindowsSpeechService(AppSettings settings) {
    final engine = AppSettings.normalizeSttEngine(settings.sttEngine);
    if (AppSettings.isOfflineSherpaEngine(engine)) {
      final spec = OfflineSttModelCatalog.engineById(engine);
      _offlineSherpaSttService.configureEngine(engine);
      final script = _currentScript;
      final hintWords =
          settings.sttOfflineScriptBoostEnabled && script != null
              ? SherpaHotwordsBuilder.selectScriptWords(
                script.words
                    .where((w) => !w.isNewline)
                    .map((w) => w.raw)
                    .toList(growable: false),
                startIndex: _currentState.confirmedWordIndex,
              )
              : const <String>[];
      _offlineSherpaSttService.configureSessionHints(
        scriptBoostEnabled: settings.sttOfflineScriptBoostEnabled,
        scriptWords: hintWords,
      );
      _activeSttCanSwitchLocale = true;
      _activeSttEngineLabel =
          spec == null
              ? 'Offline speech-to-text'
              : 'Offline ${spec.shortLabel}';
      return _offlineSherpaSttService;
    }
    _activeSttCanSwitchLocale = true;
    _activeSttEngineLabel = 'Hidden in-app speech-to-text';
    return _browserSttService;
  }
}
