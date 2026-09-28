part of 'teleprompter_provider.dart';

extension TeleprompterNotifierRelock on TeleprompterNotifier {
  List<String> _recentTranscriptWindows(String transcript) =>
      TeleprompterNotifier.liveTranscriptWindowsForAlignment(transcript);

  AbstractSttService _resolveWindowsSpeechService(AppSettings _) {
    // V5 production speech is intentionally locked to the app's hidden
    // embedded WebView. Persisted legacy engine values must not revive the
    // desktop, external-browser, or future Whisper paths.
    _activeSttCanSwitchLocale = true;
    _activeSttEngineLabel = 'Hidden in-app speech-to-text';
    return _browserSttService;
  }
}
