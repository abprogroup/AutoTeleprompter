import '../../../platform/stt/abstract_stt_service.dart';

/// Sentinel to explicitly clear a nullable field via copyWith
const _clearSentinel = '\x00__CLEAR__';

class TeleprompterState {
  final int confirmedWordIndex;
  final bool isListening;
  final bool isStarting;
  final String statusMessage;
  final bool hasError;
  final List<String> debugLogs;

  /// Non-null when the script's language isn't available for Google STT.
  /// The UI should show a dialog prompting the user to download it.
  final String? missingLanguage;

  /// Live microphone input level: 0.0 (silent) to 1.0 (max).
  /// Only meaningful when isListening.
  final double soundLevel;

  /// URL of the embedded STT WebView (Windows only). Null on other platforms.
  final String? sttWebViewUrl;

  /// Audio input devices discovered by the active STT adapter.
  final List<SttAudioInputDevice> audioInputDevices;

  const TeleprompterState({
    this.confirmedWordIndex = 0,
    this.isListening = false,
    this.isStarting = false,
    this.statusMessage = '',
    this.hasError = false,
    this.debugLogs = const [],
    this.missingLanguage,
    this.soundLevel = 0.0,
    this.sttWebViewUrl,
    this.audioInputDevices = const [],
  });

  TeleprompterState copyWith({
    int? confirmedWordIndex,
    bool? isListening,
    bool? isStarting,
    String? statusMessage,
    bool? hasError,
    List<String>? debugLogs,
    String? missingLanguage = _clearSentinel,
    double? soundLevel,
    String? sttWebViewUrl = _clearSentinel,
    List<SttAudioInputDevice>? audioInputDevices,
  }) {
    return TeleprompterState(
      confirmedWordIndex: confirmedWordIndex ?? this.confirmedWordIndex,
      isListening: isListening ?? this.isListening,
      isStarting: isStarting ?? this.isStarting,
      statusMessage: statusMessage ?? this.statusMessage,
      hasError: hasError ?? this.hasError,
      debugLogs: debugLogs ?? this.debugLogs,
      missingLanguage: missingLanguage == _clearSentinel
          ? this.missingLanguage
          : missingLanguage,
      soundLevel: soundLevel ?? this.soundLevel,
      sttWebViewUrl:
          sttWebViewUrl == _clearSentinel ? this.sttWebViewUrl : sttWebViewUrl,
      audioInputDevices: audioInputDevices ?? this.audioInputDevices,
    );
  }
}
