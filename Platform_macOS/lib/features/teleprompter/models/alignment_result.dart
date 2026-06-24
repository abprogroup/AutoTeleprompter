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

  /// Live microphone input level: 0.0 (silent) → 1.0 (max). Only meaningful when isListening.
  final double soundLevel;

  /// URL of an optional embedded STT browser surface. Null on macOS.
  final String? sttBrowserUrl;

  /// Audio input devices discovered by the active STT adapter.
  final List<SttAudioInputDevice> audioInputDevices;

  /// Apple STT health state used for coaching and diagnostics.
  final String sttHealth;
  final String sttQualityMessage;
  final double sttRecognitionQuality;

  const TeleprompterState({
    this.confirmedWordIndex = 0,
    this.isListening = false,
    this.isStarting = false,
    this.statusMessage = '',
    this.hasError = false,
    this.debugLogs = const [],
    this.missingLanguage,
    this.soundLevel = 0.0,
    this.sttBrowserUrl,
    this.audioInputDevices = const [],
    this.sttHealth = 'healthy',
    this.sttQualityMessage = '',
    this.sttRecognitionQuality = 1.0,
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
    String? sttBrowserUrl = _clearSentinel,
    List<SttAudioInputDevice>? audioInputDevices,
    String? sttHealth,
    String? sttQualityMessage,
    double? sttRecognitionQuality,
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
      sttBrowserUrl:
          sttBrowserUrl == _clearSentinel ? this.sttBrowserUrl : sttBrowserUrl,
      audioInputDevices: audioInputDevices ?? this.audioInputDevices,
      sttHealth: sttHealth ?? this.sttHealth,
      sttQualityMessage: sttQualityMessage ?? this.sttQualityMessage,
      sttRecognitionQuality:
          sttRecognitionQuality ?? this.sttRecognitionQuality,
    );
  }
}
