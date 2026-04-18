import '../../features/teleprompter/services/speech_service.dart';

/// Platform-agnostic contract for Speech-to-Text services.
///
/// All platform-specific adapters extend this class.
/// Feature code (e.g. TeleprompterNotifier) only ever references
/// AbstractSttService — it never imports platform-specific types directly.
abstract class AbstractSttService {
  /// Called for every transcription result (partial or final).
  void Function(SpeechResult)? onResult;

  /// Called when listening state changes.
  void Function(SpeechStatus)? onStatusChange;

  /// Called on STT error. Receive the raw error string.
  void Function(String error)? onError;
  
  /// Called for sound level changes (audio telemetry).
  void Function(double level)? onSoundLevelChange;
  
  /// Called when the requested language is not installed on the device.
  void Function(String requestedLocale)? onLanguageUnavailable;

  /// Android-only: fired when the Google STT cloud fallback also fails,
  /// meaning an offline language pack must be downloaded.
  /// On iOS, macOS, and Windows this callback will NEVER fire.
  void Function(String locale)? onNeedLanguagePack;

  /// Starts speech recognition.
  Future<SpeechStartResult> start({String? localeId});

  /// Stops speech recognition.
  Future<void> stop();

  /// Whether the service is currently listening.
  bool get isListening;

  /// Human-readable platform identifier used in debug logs.
  String get platformName;

  /// True if the service fires onStatusChange(listening) asynchronously
  /// after start() returns, requiring the caller to set isListening
  /// immediately rather than waiting for the callback.
  ///
  /// Apple (iOS / macOS): true — SFSpeechRecognizer callbacks are async.
  /// Android / Windows: false — status callback arrives fast enough.
  bool get requiresImmediateListeningFlag => false;
}
