part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  List<String> _recentTranscriptWindows(String transcript) =>
      TeleprompterNotifier.liveTranscriptWindowsForAlignment(transcript);

  AbstractSttService _resolveWindowsSpeechService(
    AppSettings settings,
    String initialLocale,
  ) {
    final useOffline = TeleprompterNotifier.shouldUseWindowsOfflineSpeech(
      settings: settings,
      initialLocale: initialLocale,
      sectionLocales: _sectionLocales,
    );
    _activeSttCanSwitchLocale = !useOffline;
    _activeSttEngineLabel = useOffline
        ? 'Windows built-in speech-to-text'
        : 'Browser online speech-to-text';
    return useOffline ? _desktopSttService : _browserSttService;
  }
}
