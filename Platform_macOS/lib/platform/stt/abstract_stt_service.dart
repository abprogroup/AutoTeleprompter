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

  /// Called for sound level changes (audio telemetry).
  void Function(double level)? onSoundLevelChange;

  /// Called when the requested language is not installed on the device.
  void Function(String requestedLocale)? onLanguageUnavailable;

  /// Called with diagnostic messages (init result, locale list, etc.) for the debug panel.
  void Function(String message)? onDiagnostic;

  /// Called when the platform adapter discovers audio input devices.
  void Function(List<SttAudioInputDevice> devices)? onAudioInputDevicesChanged;

  /// Optional embedded STT browser URL for adapters that expose one.
  /// Null on Apple-native adapters.
  String? get sttBrowserUrl => null;

  /// Optional platform callback when extra recognition resources are needed.
  /// Apple-native adapters do not fire this callback.
  void Function(String locale)? onNeedLanguagePack;

  /// Hot-switch the recognition locale without restarting the whole session.
  /// Default no-op; browser adapter overrides to send a WebSocket message.
  void setLocale(String locale) {}

  /// Select the preferred audio input device for adapters that can route it.
  /// Default no-op for Apple-native macOS STT.
  void setAudioInputDevice(String? deviceId, {String? label}) {}

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
  /// Apple (iOS / macOS): true because SFSpeechRecognizer callbacks are async.
  /// Other adapters: false when status callback arrives fast enough.
  bool get requiresImmediateListeningFlag => false;
}
