part of 'whisper_speech_service_native.dart';

extension WhisperSpeechServiceModelOperations on WhisperSpeechService {
  Future<WhisperModelReadiness> _modelReadiness(WhisperModel model) async {
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
        final digestMatches =
            expectedDigest == null ||
            (markerJson['sha256'] == expectedDigest &&
                await _fileDigest(files.model) == expectedDigest);
        final valid =
            markerJson['schema'] == _modelMarkerSchema &&
            markerJson['model'] == model.modelName &&
            recordedBytes is int &&
            recordedBytes == bytes &&
            digestMatches &&
            isPlausibleWhisperModelSize(model, bytes);
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

  Future<bool> _isModelDownloaded(WhisperModel model) async {
    try {
      return await _modelReadiness(model) == WhisperModelReadiness.ready;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) async {
    if (_disposed) return false;
    if (_downloadInProgress) {
      WhisperSpeechService._safeProgress(
        onProgress,
        'Another offline model download is active.',
      );
      return false;
    }

    _downloadInProgress = true;
    final generation = ++_downloadGeneration;
    final client =
        HttpClient()..connectionTimeout = WhisperSpeechService._ioTimeout;
    _downloadClient = client;

    try {
      if (await _modelReadiness(model) == WhisperModelReadiness.ready) {
        WhisperSpeechService._safeProgress(
          onProgress,
          'Whisper ${model.modelName} is ready.',
        );
        return true;
      }

      final files = await _modelFiles(model, createDirectory: true);
      await _deleteIfPresent(files.partial);
      await _deleteIfPresent(files.markerTemporary);
      WhisperSpeechService._safeProgress(
        onProgress,
        'Downloading Whisper ${model.modelName}: 0%',
      );

      final request = await client
          .getUrl(model.modelUri)
          .timeout(WhisperSpeechService._ioTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
        WhisperSpeechService._ioTimeout,
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Unexpected download response');
      }

      final expectedBytes = response.contentLength;
      final maximumBytes = maximumWhisperModelBytes(model);
      if (expectedBytes > maximumBytes) {
        throw const FileSystemException('Model download exceeds size limit');
      }

      var receivedBytes = 0;
      var lastPercent = -1;
      final sink = files.partial.openWrite(mode: FileMode.writeOnly);
      try {
        await for (final chunk in response.timeout(
          WhisperSpeechService._ioTimeout,
        )) {
          if (_disposed || generation != _downloadGeneration) {
            throw const FileSystemException('Model download cancelled');
          }
          receivedBytes += chunk.length;
          if (receivedBytes > maximumBytes) {
            throw const FileSystemException(
              'Model download exceeds size limit',
            );
          }
          sink.add(chunk);

          if (expectedBytes > 0) {
            final percent = (receivedBytes * 100 ~/ expectedBytes).clamp(0, 99);
            if (percent != lastPercent) {
              lastPercent = percent;
              WhisperSpeechService._safeProgress(
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
          !isPlausibleWhisperModelSize(model, receivedBytes)) {
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

      WhisperSpeechService._safeProgress(
        onProgress,
        'Whisper ${model.modelName} is ready.',
      );
      return true;
    } catch (_) {
      try {
        final files = await _modelFiles(model);
        await _deleteIfPresent(files.partial);
        await _deleteIfPresent(files.markerTemporary);
      } catch (_) {}
      WhisperSpeechService._safeProgress(
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

  void _cancelModelDownload() {
    _downloadGeneration++;
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  Future<bool> _prepareModel(
    WhisperModel model, {
    void Function(String)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    if (_disposed) return false;
    try {
      if (await _modelReadiness(model) != WhisperModelReadiness.ready) {
        if (shouldContinue != null && !shouldContinue()) return false;
        if (model == WhisperModel.tiny) {
          WhisperSpeechService._safeProgress(
            onProgress,
            'Preparing the bundled Whisper Tiny model.',
          );
          await _installBundledTinyModel();
        }
        if (shouldContinue != null && !shouldContinue()) return false;
        if (await _modelReadiness(model) != WhisperModelReadiness.ready) {
          final downloaded = await _downloadModel(
            model: model,
            onProgress: onProgress,
          );
          if (!downloaded) return false;
        }
      }
      if (shouldContinue != null && !shouldContinue()) return false;
      _activeModel = model;
      WhisperSpeechService._safeProgress(
        onProgress,
        'Whisper ${model.modelName} is ready.',
      );
      return true;
    } catch (_) {
      WhisperSpeechService._safeProgress(
        onProgress,
        'The offline model could not be checked.',
      );
      return false;
    }
  }

  Future<WhisperModelFiles> _modelFiles(
    WhisperModel model, {
    bool createDirectory = false,
  }) async {
    final directory = Directory(await WhisperController.getModelDir());
    if (createDirectory) await directory.create(recursive: true);
    return WhisperModelFiles.inDirectory(directory.path, model);
  }

  Future<bool> _installBundledTinyModel() async {
    final files = await _modelFiles(WhisperModel.tiny, createDirectory: true);
    try {
      final asset = await rootBundle.load(_bundledTinyModelAsset);
      final bytes = asset.lengthInBytes;
      if (_disposed || !isPlausibleWhisperModelSize(WhisperModel.tiny, bytes)) {
        return false;
      }
      final assetBytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      if (sha256.convert(assetBytes).toString() != _tinyModelSha256) {
        return false;
      }

      await _deleteIfPresent(files.partial);
      await _deleteIfPresent(files.markerTemporary);
      await files.partial.writeAsBytes(assetBytes, flush: true);
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
}

String? _expectedModelDigest(WhisperModel model) =>
    model == WhisperModel.tiny ? _tinyModelSha256 : null;

Future<String> _fileDigest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) await file.delete();
}
