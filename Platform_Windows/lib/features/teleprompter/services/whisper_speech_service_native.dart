import 'dart:async';
import 'speech_service.dart';

// Windows stub — whisper_flutter_new and record are iOS/macOS only.
// This file satisfies the same public API so teleprompter_provider.dart compiles.

enum WhisperModel { tiny, base, small, medium }

extension WhisperModelExt on WhisperModel {
  String get modelName => name;
  String getPath(String dir) => '$dir/ggml-$name.bin';
}

WhisperModel whisperModelFromEngine(String engine) {
  switch (engine) {
    case 'whisper_tiny':   return WhisperModel.tiny;
    case 'whisper_small':  return WhisperModel.small;
    case 'whisper_medium': return WhisperModel.medium;
    case 'whisper_base':
    default:               return WhisperModel.base;
  }
}

class WhisperModelInfo {
  final String engineKey;
  final String label;
  final String size;
  final String description;
  final WhisperModel model;
  const WhisperModelInfo({
    required this.engineKey,
    required this.label,
    required this.size,
    required this.description,
    required this.model,
  });
}

const whisperModels = [
  WhisperModelInfo(engineKey: 'whisper_tiny',   label: 'Whisper Tiny',   size: '~75MB',   description: 'Fastest. Best for real-time prompting.', model: WhisperModel.tiny),
  WhisperModelInfo(engineKey: 'whisper_base',   label: 'Whisper Base',   size: '~142MB',  description: 'Good balance of speed and accuracy.',     model: WhisperModel.base),
  WhisperModelInfo(engineKey: 'whisper_small',  label: 'Whisper Small',  size: '~466MB',  description: 'More accurate. Needs a decent phone.',     model: WhisperModel.small),
  WhisperModelInfo(engineKey: 'whisper_medium', label: 'Whisper Medium', size: '~1.5GB',  description: 'Most accurate. Needs a powerful phone.',   model: WhisperModel.medium),
];

/// Windows stub — Whisper offline STT is not available on Windows.
/// All methods are no-ops; the provider falls back to speech_to_text (Google STT).
class WhisperSpeechService {
  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;

  Future<bool> isModelDownloaded(WhisperModel model) async => false;

  Future<bool> downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) async {
    onProgress?.call('Whisper not supported on Windows');
    return false;
  }

  Future<bool> initialize({
    required WhisperModel model,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('Whisper not supported on Windows');
    return false;
  }

  Future<void> start({String? localeId, WhisperModel? model}) async {
    onError?.call('Whisper offline STT is not available on Windows');
  }

  Future<void> stop() async {}
  Future<void> pause() async {}

  bool get isListening => false;

  Future<void> dispose() async {}
}
