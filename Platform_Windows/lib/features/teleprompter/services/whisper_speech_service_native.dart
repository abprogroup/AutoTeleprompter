import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'speech_service.dart';

export 'package:whisper_ggml/whisper_ggml.dart' show WhisperModel;

const int _mib = 1024 * 1024;
const int _modelMarkerSchema = 1;
const String _bundledTinyModelAsset = 'assets/models/ggml-tiny.bin';
const String _tinyModelSha256 =
    'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21';

enum WhisperModelReadiness { missing, incomplete, invalid, ready }

extension WhisperModelPathExt on WhisperModel {
  String getPath(String directory) =>
      path.join(directory, whisperModelFileName(this));
}

String whisperModelFileName(WhisperModel model) =>
    'ggml-${model.modelName}.bin';

WhisperModel whisperModelFromEngine(String engine) {
  switch (engine) {
    case 'whisper_base':
      return WhisperModel.base;
    case 'whisper_small':
      return WhisperModel.small;
    case 'whisper_medium':
      return WhisperModel.medium;
    case 'whisper_tiny':
    default:
      return WhisperModel.tiny;
  }
}

String whisperLanguageForLocale(String? localeId) {
  final normalized = localeId?.trim().toLowerCase() ?? '';
  final language =
      normalized.isEmpty ? '' : normalized.split(RegExp(r'[-_]')).first;
  if (language == 'he' || language == 'iw') return 'he';
  if (language == 'en') return 'en';
  return 'auto';
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
  WhisperModelInfo(
    engineKey: 'whisper_tiny',
    label: 'Whisper Tiny',
    size: '~75MB',
    description: 'Fastest multilingual model. Recommended for live prompting.',
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
    description: 'More accurate. Needs a capable PC.',
    model: WhisperModel.small,
  ),
  WhisperModelInfo(
    engineKey: 'whisper_medium',
    label: 'Whisper Medium',
    size: '~1.5GB',
    description: 'Most accurate option. Needs a powerful PC.',
    model: WhisperModel.medium,
  ),
];

class WhisperSpeechService {
  static const _startupTimeout = Duration(seconds: 60);
  static const _ioTimeout = Duration(seconds: 30);
  static const _shortStopTimeout = Duration(seconds: 3);
  static const _nativeStopTimeout = Duration(seconds: 10);

  final AudioRecorder _recorder = AudioRecorder();

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;

  WhisperModel _activeModel = WhisperModel.tiny;
  WhisperLiveSession? _liveSession;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<String>? _partialSubscription;
  Future<WhisperLiveSession>? _pendingNativeStart;
  Future<void>? _shutdownInFlight;
  HttpClient? _downloadClient;
  int _sessionGeneration = 0;
  int _downloadGeneration = 0;
  bool _downloadInProgress = false;
  bool _recorderStarted = false;
  bool _starting = false;
  bool _isListening = false;
  bool _disposed = false;
  String _lastTranscript = '';

  bool get isListening => _isListening;

  Future<WhisperModelReadiness> modelReadiness(
    WhisperModel model,
  ) async {
    final files = await _modelFiles(model);
    final modelExists = await files.model.exists();
    final markerExists = await files.marker.exists();

    if (modelExists && markerExists) {
      try {
        final markerJson = jsonDecode(await files.marker.readAsString());
        if (markerJson is! Map<String, dynamic>) {
          return WhisperModelReadiness.invalid;
        }
        final bytes = await files.model.length();
        final recordedBytes = markerJson['bytes'];
        final expectedDigest = _expectedModelDigest(model);
        final digestMatches = expectedDigest == null ||
            (markerJson['sha256'] == expectedDigest &&
                await _fileDigest(files.model) == expectedDigest);
        final valid = markerJson['schema'] == _modelMarkerSchema &&
            markerJson['model'] == model.modelName &&
            recordedBytes is int &&
            recordedBytes == bytes &&
            digestMatches &&
            _isPlausibleModelSize(model, bytes);
        return valid
            ? WhisperModelReadiness.ready
            : WhisperModelReadiness.invalid;
      } catch (_) {
        return WhisperModelReadiness.invalid;
      }
    }

    if (await files.partial.exists()) {
      return WhisperModelReadiness.incomplete;
    }
    if (modelExists || markerExists) return WhisperModelReadiness.invalid;
    return WhisperModelReadiness.missing;
  }

  Future<bool> isModelDownloaded(WhisperModel model) async {
    try {
      return await modelReadiness(model) == WhisperModelReadiness.ready;
    } catch (_) {
      return false;
    }
  }

  Future<bool> downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) async {
    if (_disposed) return false;
    if (_downloadInProgress) {
      _safeProgress(onProgress, 'Another offline model download is active.');
      return false;
    }

    _downloadInProgress = true;
    final generation = ++_downloadGeneration;
    final client = HttpClient()..connectionTimeout = _ioTimeout;
    _downloadClient = client;

    try {
      if (await modelReadiness(model) == WhisperModelReadiness.ready) {
        _safeProgress(onProgress, 'Whisper ${model.modelName} is ready.');
        return true;
      }

      final files = await _modelFiles(model, createDirectory: true);
      await _deleteIfPresent(files.partial);
      await _deleteIfPresent(files.markerTemporary);
      _safeProgress(onProgress, 'Downloading Whisper ${model.modelName}: 0%');

      final request = await client.getUrl(model.modelUri).timeout(_ioTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(_ioTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Unexpected download response');
      }

      final expectedBytes = response.contentLength;
      final maximumBytes = _maximumModelBytes(model);
      if (expectedBytes > maximumBytes) {
        throw const FileSystemException('Model download exceeds size limit');
      }

      var receivedBytes = 0;
      var lastPercent = -1;
      final sink = files.partial.openWrite(mode: FileMode.writeOnly);
      try {
        await for (final chunk in response.timeout(_ioTimeout)) {
          if (_disposed || generation != _downloadGeneration) {
            throw const FileSystemException('Model download cancelled');
          }
          receivedBytes += chunk.length;
          if (receivedBytes > maximumBytes) {
            throw const FileSystemException(
                'Model download exceeds size limit');
          }
          sink.add(chunk);

          if (expectedBytes > 0) {
            final percent = (receivedBytes * 100 ~/ expectedBytes).clamp(0, 99);
            if (percent != lastPercent) {
              lastPercent = percent;
              _safeProgress(
                onProgress,
                'Downloading Whisper ${model.modelName}: $percent%',
              );
            }
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (_disposed || generation != _downloadGeneration) {
        throw const FileSystemException('Model download cancelled');
      }
      if ((expectedBytes > 0 && receivedBytes != expectedBytes) ||
          !_isPlausibleModelSize(model, receivedBytes)) {
        throw const FileSystemException('Incomplete model download');
      }
      final expectedDigest = _expectedModelDigest(model);
      final actualDigest = await _fileDigest(files.partial);
      if (expectedDigest != null && actualDigest != expectedDigest) {
        throw const FileSystemException('Model checksum verification failed');
      }

      await files.markerTemporary.writeAsString(
        jsonEncode({
          'schema': _modelMarkerSchema,
          'model': model.modelName,
          'bytes': receivedBytes,
          if (expectedDigest != null) 'sha256': actualDigest,
        }),
        flush: true,
      );
      await _deleteIfPresent(files.model);
      await _deleteIfPresent(files.marker);
      await files.partial.rename(files.model.path);
      await files.markerTemporary.rename(files.marker.path);

      _safeProgress(onProgress, 'Whisper ${model.modelName} is ready.');
      return true;
    } catch (_) {
      try {
        final files = await _modelFiles(model);
        await _deleteIfPresent(files.partial);
        await _deleteIfPresent(files.markerTemporary);
      } catch (_) {}
      _safeProgress(
        onProgress,
        'Model download failed. Check your connection and try again.',
      );
      return false;
    } finally {
      client.close(force: true);
      if (identical(_downloadClient, client)) _downloadClient = null;
      _downloadInProgress = false;
    }
  }

  void cancelModelDownload() {
    _downloadGeneration++;
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  Future<bool> initialize({
    required WhisperModel model,
    void Function(String)? onProgress,
  }) =>
      _prepareModel(model, onProgress: onProgress);

  Future<bool> _prepareModel(
    WhisperModel model, {
    void Function(String)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    if (_disposed) return false;
    try {
      if (await modelReadiness(model) != WhisperModelReadiness.ready) {
        if (shouldContinue != null && !shouldContinue()) return false;
        if (model == WhisperModel.tiny) {
          _safeProgress(
              onProgress, 'Preparing the bundled Whisper Tiny model.');
          await _installBundledTinyModel();
        }
        if (shouldContinue != null && !shouldContinue()) return false;
        if (await modelReadiness(model) != WhisperModelReadiness.ready) {
          final downloaded = await downloadModel(
            model: model,
            onProgress: onProgress,
          );
          if (!downloaded) return false;
        }
      }
      if (shouldContinue != null && !shouldContinue()) return false;
      _activeModel = model;
      _safeProgress(onProgress, 'Whisper ${model.modelName} is ready.');
      return true;
    } catch (_) {
      _safeProgress(onProgress, 'The offline model could not be checked.');
      return false;
    }
  }

  Future<void> start({String? localeId, WhisperModel? model}) async {
    if (_disposed) return;
    await _endSession(SpeechStatus.idle, notify: false);
    if (_disposed) return;
    if (_pendingNativeStart != null) {
      _emitStartFailure(
        'Whisper init failed: the previous offline session is still closing.',
      );
      return;
    }

    final generation = ++_sessionGeneration;
    final selectedModel = model ?? _activeModel;
    _starting = true;
    _lastTranscript = '';

    try {
      if (!await _prepareModel(
        selectedModel,
        shouldContinue: () => _isCurrent(generation),
      )) {
        await _failStart(
          generation,
          'Whisper init failed: the offline model is not available.',
        );
        return;
      }
      if (!_isCurrent(generation)) return;

      if (!await _recorder.hasPermission()) {
        await _failStart(
          generation,
          'Whisper init failed: microphone permission is required.',
        );
        return;
      }
      if (!_isCurrent(generation)) return;

      if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
        await _failStart(
          generation,
          'Whisper init failed: PCM microphone streaming is unavailable.',
        );
        return;
      }
      if (!_isCurrent(generation)) return;

      final files = await _modelFiles(selectedModel);
      final nativeStart = startWhisperLiveSession(
        modelPath: files.model.path,
        lang: whisperLanguageForLocale(localeId),
        suppressNonSpeechTokens: true,
        keepModelLoaded: false,
      );
      _pendingNativeStart = nativeStart;
      _cleanUpLateNativeStart(nativeStart, generation);

      final session = await nativeStart.timeout(_startupTimeout);
      if (identical(_pendingNativeStart, nativeStart)) {
        _pendingNativeStart = null;
      }
      if (!_isCurrent(generation)) {
        await _stopNativeSession(session);
        return;
      }

      _liveSession = session;
      _partialSubscription = session.partials.listen(
        (transcript) => _handlePartial(generation, transcript),
        onError: (_) => _handleSessionFailure(generation),
      );

      _recorderStarted = true;
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      if (!_isCurrent(generation)) {
        await _stopRecorder();
        return;
      }

      _audioSubscription = audioStream.listen(
        (bytes) {
          if (_isCurrent(generation) && _isListening) {
            session.feed(bytes);
          }
        },
        onError: (_) => _handleAudioFailure(generation),
        onDone: () => _handleAudioFailure(generation),
        cancelOnError: true,
      );
      _activeModel = selectedModel;
      _starting = false;
      _isListening = true;
      _emitStatus(SpeechStatus.listening);
    } on TimeoutException {
      await _failStart(
        generation,
        'Whisper init failed: the offline engine took too long to start.',
      );
    } catch (_) {
      await _failStart(
        generation,
        'Whisper init failed: the offline engine could not start.',
      );
    }
  }

  Future<void> stop() => _endSession(SpeechStatus.idle);

  Future<void> pause() => _endSession(SpeechStatus.paused);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelModelDownload();
    await _endSession(SpeechStatus.idle, notify: false);
    await _ignoreErrors(
      _recorder.dispose(),
      timeout: _shortStopTimeout,
    );
  }

  void _handlePartial(int generation, String transcript) {
    if (!_isCurrent(generation) || !_isListening) return;
    final normalized = transcript.trim();
    if (normalized.isEmpty || normalized == _lastTranscript) return;
    _lastTranscript = normalized;
    try {
      onResult?.call(SpeechResult(normalized, false));
    } catch (_) {}
  }

  void _handleAudioFailure(int generation) {
    if (!_isCurrent(generation) || !_isListening) return;
    _emitError('Whisper audio input stopped unexpectedly.');
    _emitStatus(SpeechStatus.error);
    unawaited(_endSession(SpeechStatus.error, notify: false));
  }

  void _handleSessionFailure(int generation) {
    if (!_isCurrent(generation)) return;
    _emitError('Whisper transcription stopped unexpectedly.');
    _emitStatus(SpeechStatus.error);
    unawaited(_endSession(SpeechStatus.error, notify: false));
  }

  Future<void> _failStart(int generation, String message) async {
    if (!_isCurrent(generation)) return;
    _emitError(message);
    _emitStatus(SpeechStatus.error);
    await _endSession(SpeechStatus.error, notify: false);
  }

  void _emitStartFailure(String message) {
    _emitError(message);
    _emitStatus(SpeechStatus.error);
  }

  Future<void> _endSession(
    SpeechStatus status, {
    bool notify = true,
  }) async {
    _sessionGeneration++;
    final cancelStartupDownload = _starting;
    _starting = false;
    _isListening = false;
    if (cancelStartupDownload) cancelModelDownload();

    final existingShutdown = _shutdownInFlight;
    if (existingShutdown != null) {
      await existingShutdown;
      if (notify && !_disposed) _emitStatus(status);
      return;
    }

    final shutdown = _tearDownSession();
    _shutdownInFlight = shutdown;
    try {
      await shutdown;
    } finally {
      if (identical(_shutdownInFlight, shutdown)) {
        _shutdownInFlight = null;
      }
    }
    if (notify && !_disposed) _emitStatus(status);
  }

  Future<void> _tearDownSession() async {
    final audioSubscription = _audioSubscription;
    final partialSubscription = _partialSubscription;
    final liveSession = _liveSession;
    final pendingNativeStart = _pendingNativeStart;
    _audioSubscription = null;
    _partialSubscription = null;
    _liveSession = null;
    _lastTranscript = '';

    if (audioSubscription != null) {
      await _ignoreErrors(
        audioSubscription.cancel(),
        timeout: _shortStopTimeout,
      );
    }
    await _stopRecorder();
    if (partialSubscription != null) {
      await _ignoreErrors(
        partialSubscription.cancel(),
        timeout: _shortStopTimeout,
      );
    }
    if (liveSession != null) await _stopNativeSession(liveSession);

    if (liveSession == null && pendingNativeStart != null) {
      try {
        final lateSession = await pendingNativeStart.timeout(
          _shortStopTimeout,
        );
        await _stopNativeSession(lateSession);
      } catch (_) {}
    }
  }

  Future<void> _stopRecorder() async {
    if (!_recorderStarted) return;
    _recorderStarted = false;
    await _ignoreErrors(
      _recorder.stop(),
      timeout: _shortStopTimeout,
    );
  }

  Future<void> _stopNativeSession(WhisperLiveSession session) =>
      _ignoreErrors(session.stop(), timeout: _nativeStopTimeout);

  void _cleanUpLateNativeStart(
    Future<WhisperLiveSession> nativeStart,
    int generation,
  ) {
    unawaited(
      nativeStart.then<void>((session) {
        if (!_isCurrent(generation)) {
          unawaited(_stopNativeSession(session));
        }
      }, onError: (_) {}).whenComplete(() {
        if (identical(_pendingNativeStart, nativeStart)) {
          _pendingNativeStart = null;
        }
      }),
    );
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _sessionGeneration;

  void _emitError(String message) {
    if (_disposed) return;
    try {
      onError?.call(message);
    } catch (_) {}
  }

  void _emitStatus(SpeechStatus status) {
    if (_disposed) return;
    try {
      onStatusChange?.call(status);
    } catch (_) {}
  }

  static void _safeProgress(
    void Function(String)? callback,
    String message,
  ) {
    try {
      callback?.call(message);
    } catch (_) {}
  }

  static Future<void> _ignoreErrors<T>(
    Future<T> operation, {
    required Duration timeout,
  }) async {
    try {
      await operation.timeout(timeout);
    } catch (_) {}
  }

  Future<_WhisperModelFiles> _modelFiles(
    WhisperModel model, {
    bool createDirectory = false,
  }) async {
    final directory = Directory(await WhisperController.getModelDir());
    if (createDirectory) await directory.create(recursive: true);
    final modelPath = path.join(directory.path, whisperModelFileName(model));
    return _WhisperModelFiles(modelPath);
  }

  Future<bool> _installBundledTinyModel() async {
    final files = await _modelFiles(
      WhisperModel.tiny,
      createDirectory: true,
    );
    try {
      final asset = await rootBundle.load(_bundledTinyModelAsset);
      final bytes = asset.lengthInBytes;
      if (_disposed || !_isPlausibleModelSize(WhisperModel.tiny, bytes)) {
        return false;
      }
      final assetBytes =
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
      if (sha256.convert(assetBytes).toString() != _tinyModelSha256) {
        return false;
      }

      await _deleteIfPresent(files.partial);
      await _deleteIfPresent(files.markerTemporary);
      await files.partial.writeAsBytes(
        assetBytes,
        flush: true,
      );
      if (await files.partial.length() != bytes) {
        throw const FileSystemException('Incomplete bundled model copy');
      }
      await files.markerTemporary.writeAsString(
        jsonEncode({
          'schema': _modelMarkerSchema,
          'model': WhisperModel.tiny.modelName,
          'bytes': bytes,
          'sha256': _tinyModelSha256,
        }),
        flush: true,
      );
      if (_disposed) throw const FileSystemException('Model copy cancelled');
      await _deleteIfPresent(files.model);
      await _deleteIfPresent(files.marker);
      await files.partial.rename(files.model.path);
      await files.markerTemporary.rename(files.marker.path);
      return true;
    } catch (_) {
      try {
        await _deleteIfPresent(files.partial);
        await _deleteIfPresent(files.markerTemporary);
      } catch (_) {}
      return false;
    }
  }

  static bool _isPlausibleModelSize(WhisperModel model, int bytes) =>
      bytes >= _minimumModelBytes(model) && bytes <= _maximumModelBytes(model);

  static String? _expectedModelDigest(WhisperModel model) =>
      model == WhisperModel.tiny ? _tinyModelSha256 : null;

  static Future<String> _fileDigest(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static int _minimumModelBytes(WhisperModel model) {
    switch (model) {
      case WhisperModel.tiny:
      case WhisperModel.tinyEn:
        return 50 * _mib;
      case WhisperModel.base:
      case WhisperModel.baseEn:
        return 100 * _mib;
      case WhisperModel.small:
      case WhisperModel.smallEn:
      case WhisperModel.smallEnTdrz:
        return 300 * _mib;
      case WhisperModel.medium:
      case WhisperModel.mediumEn:
        return 900 * _mib;
      case WhisperModel.large:
        return 2000 * _mib;
    }
  }

  static int _maximumModelBytes(WhisperModel model) {
    switch (model) {
      case WhisperModel.tiny:
      case WhisperModel.tinyEn:
        return 200 * _mib;
      case WhisperModel.base:
      case WhisperModel.baseEn:
        return 400 * _mib;
      case WhisperModel.small:
      case WhisperModel.smallEn:
      case WhisperModel.smallEnTdrz:
        return 1200 * _mib;
      case WhisperModel.medium:
      case WhisperModel.mediumEn:
        return 3500 * _mib;
      case WhisperModel.large:
        return 7000 * _mib;
    }
  }

  static Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}

class _WhisperModelFiles {
  _WhisperModelFiles(String modelPath)
      : model = File(modelPath),
        partial = File('$modelPath.part'),
        marker = File('$modelPath.complete.json'),
        markerTemporary = File('$modelPath.complete.json.part');

  final File model;
  final File partial;
  final File marker;
  final File markerTemporary;
}
