import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'speech_service.dart';

/// Maps engine setting strings to WhisperModel
WhisperModel whisperModelFromEngine(String engine) {
  switch (engine) {
    case 'whisper_tiny': return WhisperModel.tiny;
    case 'whisper_small': return WhisperModel.small;
    case 'whisper_medium': return WhisperModel.medium;
    case 'whisper_base':
    default: return WhisperModel.base;
  }
}

/// Model info for the settings UI
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
  WhisperModelInfo(
    engineKey: 'whisper_tiny',
    label: 'Whisper Tiny',
    size: '~75MB',
    description: 'Fastest. Best for real-time prompting.',
    model: WhisperModel.tiny,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_base',
    label: 'Whisper Base',
    size: '~142MB',
    description: 'Good balance of speed and accuracy.',
    model: WhisperModel.base,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_small',
    label: 'Whisper Small',
    size: '~466MB',
    description: 'More accurate. Needs a decent phone.',
    model: WhisperModel.small,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_medium',
    label: 'Whisper Medium',
    size: '~1.5GB',
    description: 'Most accurate. Needs a powerful phone.',
    model: WhisperModel.medium,
  ),
];

/// Whisper-based speech service — works offline on all devices.
///
/// v4.0 Sequential chunk design:
/// Audio streams continuously. Every ~400ms we check if there's enough new
/// audio (~0.6-0.8s) and transcribe ONLY the new chunk. After transcription,
/// the committed audio is cleared. This keeps each inference under 1 second
/// even on slow phones, because whisper.cpp scales non-linearly with audio
/// length (0.6s audio → ~600ms inference, but 1.5s audio → ~4s inference).
///
/// Results are accumulated into _fullTranscript and sent to the provider
/// for word alignment against the script.
class WhisperSpeechService {
  final AudioRecorder _recorder = AudioRecorder();
  Whisper? _whisper;
  bool _isActive = false;
  bool _isTranscribing = false;
  bool _isModelReady = false;
  String _language = 'auto';
  Timer? _transcribeTimer;
  WhisperModel _activeModel = WhisperModel.base;
  StreamSubscription<Uint8List>? _audioStreamSub;

  static const int _sampleRate = 16000;
  static const int _bytesPerSample = 2;

  // Minimum audio before transcription (2.5s) — Whisper needs context for accuracy
  static final int _minChunkBytes = (_sampleRate * _bytesPerSample * 2.5).toInt();
  // Maximum chunk size to cap inference time (4s)
  static final int _maxChunkBytes = (_sampleRate * _bytesPerSample * 4.0).toInt();

  // How often to check for new audio to transcribe
  static const _transcribeInterval = Duration(milliseconds: 500);

  // Audio buffer — accumulates new audio since last transcription
  final List<int> _audioBuffer = [];

  // Full accumulated transcript across all chunks
  String _fullTranscript = '';

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;

  Future<String> _getModelDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  /// Check if a model is fully downloaded by verifying the .complete marker.
  Future<bool> isModelDownloaded(WhisperModel model) async {
    final dir = await _getModelDir();
    final modelFile = File(model.getPath(dir));
    final markerFile = File('${model.getPath(dir)}.complete');
    return modelFile.existsSync() && markerFile.existsSync();
  }

  Future<bool> downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) async {
    try {
      final info = whisperModels.firstWhere((m) => m.model == model);
      final dir = await _getModelDir();
      final modelPath = model.getPath(dir);
      final modelFile = File(modelPath);
      final markerFile = File('$modelPath.complete');

      // Already fully downloaded
      if (modelFile.existsSync() && markerFile.existsSync()) {
        onProgress?.call('Already downloaded');
        return true;
      }

      // Remove partial download and stale marker
      if (modelFile.existsSync()) modelFile.deleteSync();
      if (markerFile.existsSync()) markerFile.deleteSync();

      onProgress?.call('Downloading ${info.label} (${info.size})...');

      final whisper = Whisper(model: model, modelDir: dir);
      await whisper.getVersion(); // triggers download + validates model

      if (modelFile.existsSync()) {
        // Verify model loads correctly, then write completion marker
        markerFile.writeAsStringSync('ok');
        onProgress?.call('Download complete');
        return true;
      } else {
        onProgress?.call('Download failed');
        return false;
      }
    } catch (e) {
      onProgress?.call('Download failed: $e');
      return false;
    }
  }

  Future<void> deleteModel(WhisperModel model) async {
    final dir = await _getModelDir();
    final modelPath = model.getPath(dir);
    final modelFile = File(modelPath);
    final markerFile = File('$modelPath.complete');
    if (modelFile.existsSync()) modelFile.deleteSync();
    if (markerFile.existsSync()) markerFile.deleteSync();
    if (_activeModel == model) {
      _isModelReady = false;
      _whisper = null;
    }
  }

  Future<bool> initialize({
    required WhisperModel model,
    void Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('Loading Whisper...');

      final dir = await _getModelDir();
      final modelFile = File(model.getPath(dir));

      final markerFile = File('${modelFile.path}.complete');
      if (!modelFile.existsSync() || !markerFile.existsSync()) {
        // Clean up partial download
        if (modelFile.existsSync()) modelFile.deleteSync();
        if (markerFile.existsSync()) markerFile.deleteSync();
        onError?.call('Offline model not downloaded. Go to Settings to download.');
        return false;
      }

      _activeModel = model;
      _whisper = Whisper(model: model, modelDir: dir);

      final version = await _whisper!.getVersion();
      if (kDebugMode) debugPrint('Whisper version: $version, model: ${model.modelName}');

      _isModelReady = true;
      onProgress?.call('Whisper ready');
      return true;
    } catch (e) {
      onError?.call('Whisper init failed: $e');
      _isModelReady = false;
      return false;
    }
  }

  Future<void> start({String? localeId, WhisperModel? model}) async {
    final targetModel = model ?? _activeModel;

    if (!_isModelReady || _activeModel != targetModel) {
      final ok = await initialize(model: targetModel);
      if (!ok) {
        onError?.call('Whisper model not available');
        return;
      }
    }

    if (localeId != null) {
      if (localeId.startsWith('he')) {
        _language = 'he';
      } else if (localeId.startsWith('en')) {
        _language = 'en';
      } else {
        _language = 'auto';
      }
    }

    _isActive = true;
    _isTranscribing = false;
    _audioBuffer.clear();
    _fullTranscript = '';
    onStatusChange?.call(SpeechStatus.listening);

    await _startAudioStream();

    _transcribeTimer = Timer.periodic(_transcribeInterval, (_) {
      if (!_isActive) return;
      _transcribeChunk();
    });
  }

  Future<void> _startAudioStream() async {
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
          bitRate: 256000,
        ),
      );

      _audioStreamSub = stream.listen(
        (Uint8List chunk) {
          if (!_isActive) return;
          _audioBuffer.addAll(chunk);
        },
        onError: (e) {
          onError?.call('Audio stream error: $e');
        },
      );
    } catch (e) {
      onError?.call('Failed to start audio stream: $e');
    }
  }

  /// Transcribe only the NEW audio since last transcription.
  void _transcribeChunk() {
    if (!_isActive || _isTranscribing) return;
    if (_audioBuffer.length < _minChunkBytes) return;

    // Take at most _maxChunkBytes to keep inference fast
    final takeBytes = _audioBuffer.length.clamp(0, _maxChunkBytes);
    final pcmBytes = Uint8List.fromList(_audioBuffer.sublist(0, takeBytes));

    // Clear the committed audio immediately so new audio accumulates
    _audioBuffer.removeRange(0, takeBytes);

    _isTranscribing = true;
    _transcribeBytes(pcmBytes).then((_) {
      _isTranscribing = false;
    });
  }

  Future<void> _transcribeBytes(Uint8List pcmBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final wavPath = '${dir.path}/whisper_chunk.wav';

      _writeWav(wavPath, pcmBytes, _sampleRate, 1);

      final sw = Stopwatch()..start();
      final result = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wavPath,
          language: _language,
          isNoTimestamps: true,
          isTranslate: false,
          threads: 4,
          noFallback: true,  // Skip temperature fallback — faster
        ),
      );
      sw.stop();

      final audioMs = (pcmBytes.length / (_sampleRate * _bytesPerSample) * 1000).round();
      if (kDebugMode) debugPrint('Whisper: ${sw.elapsedMilliseconds}ms for ${audioMs}ms audio | "${result.text.trim()}"');

      try { File(wavPath).deleteSync(); } catch (_) {}

      if (!_isActive) return;

      final text = result.text.trim();

      // Filter artifacts
      if (text.isEmpty || text.length <= 1) return;
      if (_isArtifact(text)) return;

      // Append new words to full transcript
      if (_fullTranscript.isEmpty) {
        _fullTranscript = text;
      } else {
        _fullTranscript = '$_fullTranscript $text';
      }

      // Send full accumulated transcript — the provider's WordAligner
      // needs the complete text to match against the script
      onResult?.call(SpeechResult(_fullTranscript, true));

    } catch (e) {
      if (kDebugMode) debugPrint('Whisper transcription error: $e');
      if (_isActive) {
        onError?.call('Whisper error: $e');
      }
    }
  }

  bool _isArtifact(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.startsWith('[') || lower.startsWith('(')) return true;
    if (lower.contains('thank you') && lower.length < 15) return true;
    if (lower.contains('thanks for watching')) return true;
    if (lower.contains('subscribe')) return true;
    if (lower.contains('blank_audio')) return true;
    if (lower == 'you' || lower == 'the' || lower == 'a') return true;
    return false;
  }

  void _writeWav(String path, Uint8List pcmData, int sampleRate, int channels) {
    final bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final file = File(path);
    file.writeAsBytesSync([...header.buffer.asUint8List(), ...pcmData]);
  }

  Future<void> stop() async {
    _isActive = false;
    _transcribeTimer?.cancel();
    _transcribeTimer = null;
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _audioBuffer.clear();
    _fullTranscript = '';
    onStatusChange?.call(SpeechStatus.idle);

    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/whisper_chunk.wav');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> pause() async {
    _isActive = false;
    _transcribeTimer?.cancel();
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    onStatusChange?.call(SpeechStatus.paused);
  }

  bool get isListening => _isActive;

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}
