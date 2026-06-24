import '../../features/teleprompter/services/speech_service.dart';

class SttAudioInputDevice {
  final String id;
  final String label;

  const SttAudioInputDevice({
    required this.id,
    required this.label,
  });
}

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

  /// Called when the requested language is not installed on the device.
  void Function(String requestedLocale)? onLanguageUnavailable;

  /// Android-only: fired when the Google STT cloud fallback also fails,
  /// meaning an offline language pack must be downloaded.
  /// On iOS, macOS, and Windows this callback will NEVER fire.
  void Function(String locale)? onNeedLanguagePack;

  /// Fired when adapters discover/select available audio input routes.
  void Function(List<SttAudioInputDevice> devices)? onAudioInputDevicesChanged;

  /// Fired with platform-native microphone level updates when available.
  void Function(double level)? onSoundLevelChange;

  /// Starts speech recognition.
  Future<SpeechStartResult> start({String? localeId});

  /// Stops speech recognition.
  Future<void> stop();

  /// Whether the service is currently listening.
  bool get isListening;

  /// Human-readable platform identifier used in debug logs.
  String get platformName;

  /// Refresh available input devices/routes for adapters that can expose them.
  Future<List<SttAudioInputDevice>> refreshAudioInputDevices() async =>
      const [];

  /// Select the preferred audio input device/route.
  /// Empty/null means system default.
  Future<void> setAudioInputDevice(String? deviceId, {String? label}) async {}

  /// Switch the recognition locale without stopping the session.
  /// The new locale takes effect on the next recognition restart.
  /// Default is a no-op; override in adapters that support hot-switching.
  void setLocale(String locale) {}

  /// True if the service fires onStatusChange(listening) asynchronously
  /// after start() returns, requiring the caller to set isListening
  /// immediately rather than waiting for the callback.
  ///
  /// Apple (iOS / macOS): true — SFSpeechRecognizer callbacks are async.
  /// Android / Windows: false — status callback arrives fast enough.
  bool get requiresImmediateListeningFlag => false;
}
