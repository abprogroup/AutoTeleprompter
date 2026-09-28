import 'speech_service.dart';
import 'whisper_model_support.dart';

export 'whisper_model_support.dart';

/// V5 Windows compatibility stub.
///
/// Offline Whisper is future work and is intentionally not linked into the
/// Windows application. This no-op surface keeps legacy source/settings data
/// readable without constructing a native controller, loading a model, or
/// opening a second microphone pipeline.
class WhisperSpeechService {
  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;
  void Function(String)? onDiagnostic;
  void Function(double)? onSoundLevelChange;

  bool get isListening => false;

  void setPreferredInputDeviceLabel(String? label) {}

  Future<WhisperModelReadiness> modelReadiness(WhisperModel model) async =>
      WhisperModelReadiness.missing;

  Future<bool> isModelDownloaded(WhisperModel model) async => false;

  Future<bool> downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Offline speech is not available in this Windows build.');
    return false;
  }

  void cancelModelDownload() {}

  Future<bool> initialize({
    required WhisperModel model,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Offline speech is not available in this Windows build.');
    return false;
  }

  Future<void> start({String? localeId, WhisperModel? model}) async {
    onError?.call('Offline speech is not available in this Windows build.');
  }

  Future<void> stop() async {}

  Future<void> pause() async {}

  Future<void> dispose() async {}
}
