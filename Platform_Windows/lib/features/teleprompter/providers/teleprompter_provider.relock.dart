part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  List<String> _recentTranscriptWindows(String transcript) =>
      TeleprompterNotifier.liveTranscriptWindowsForAlignment(transcript);

  AbstractSttService _resolveWindowsSpeechService(AppSettings settings) {
    final useOffline = TeleprompterNotifier.shouldUseWindowsOfflineSpeech(
      settings,
    );
    final policyHost = _windowsSttHostPolicy?.currentHost;
    _useExternalEdgeSttHost =
        !useOffline &&
        (policyHost == WindowsSttBrowserHost.externalEdge ||
            (policyHost == null &&
                usesExternalEdgeSttHost(settings.sttEngine)));
    _useExternalChromeSttHost =
        !useOffline &&
        (policyHost == WindowsSttBrowserHost.externalChrome ||
            (policyHost == null &&
                usesExternalChromeSttHost(settings.sttEngine)));
    _activeSttCanSwitchLocale = !useOffline;
    _activeSttEngineLabel =
        useOffline
            ? 'Windows built-in speech-to-text'
            : _useExternalChromeSttHost
            ? 'Google Chrome compatibility speech-to-text'
            : _useExternalEdgeSttHost
            ? 'Microsoft Edge compatibility speech-to-text'
            : 'Browser online speech-to-text';
    return useOffline ? _desktopSttService : _browserSttService;
  }
}
