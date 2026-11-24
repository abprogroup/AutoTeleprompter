import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../features/settings/models/app_settings.dart';
import '../../features/teleprompter/services/speech_service.dart';
import 'abstract_stt_service.dart';
import 'offline_stt_model_catalog.dart';
import 'offline_stt_model_manager.dart';
import 'sherpa_stt_worker.dart';
import 'windows_wavein_pcm_stream.dart';

/// Windows offline speech-to-text adapter powered by `sherpa_onnx` in a
/// background isolate + `winmm.dll` 16 kHz PCM capture.
class SttSherpaAdapter extends AbstractSttService {
  SttSherpaAdapter({
    OfflineSttModelManager? modelManager,
    WindowsWaveInPcmStream? audioCapture,
  }) : _modelManager = modelManager ?? OfflineSttModelManager.instance,
       _audioCapture = audioCapture ?? WindowsWaveInPcmStream();

  final OfflineSttModelManager _modelManager;
  final WindowsWaveInPcmStream _audioCapture;

  String _engineId = AppSettings.sttEngineOfflineZipformerFast;
  bool _scriptBoostEnabled = true;
  List<String> _scriptWords = const <String>[];
  String? _preferredDeviceId;
  String? _preferredDeviceLabel;
  String _activeLocale = 'he_IL';
  bool _listening = false;
  int _sessionGeneration = 0;

  Isolate? _workerIsolate;
  ReceivePort? _workerReceivePort;
  StreamSubscription<dynamic>? _workerSub;
  SendPort? _workerSendPort;
  int _requestSequence = 0;
  final Map<int, Completer<Map<Object?, Object?>>> _pendingRequests = {};
  DateTime _lastSoundLevelEmit = DateTime.fromMillisecondsSinceEpoch(0);

  void configureEngine(String engineId) {
    if (AppSettings.isOfflineSherpaEngine(engineId)) {
      _engineId = engineId;
    }
  }

  void configureSessionHints({
    required bool scriptBoostEnabled,
    required List<String> scriptWords,
  }) {
    _scriptBoostEnabled = scriptBoostEnabled;
    _scriptWords = List<String>.unmodifiable(scriptWords);
  }

  @override
  bool get isListening => _listening;

  @override
  String get platformName {
    final spec = OfflineSttModelCatalog.engineById(_engineId);
    return spec == null ? 'windows_sherpa' : 'windows_sherpa_${spec.shortLabel}';
  }

  @override
  void setAudioInputDevice(String? deviceId, {String? label}) {
    _preferredDeviceId = deviceId;
    _preferredDeviceLabel = label;
  }

  @override
  Future<List<SttAudioInputDevice>> refreshAudioInputDevices() async {
    if (!Platform.isWindows) return const [];
    try {
      final devices = _audioCapture.listInputDevices();
      onAudioInputDevicesChanged?.call(devices);
      return devices;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    if (!Platform.isWindows) {
      return SpeechStartResult(
        success: false,
        message: 'Offline Sherpa STT is currently supported on Windows only.',
      );
    }

    final spec = OfflineSttModelCatalog.engineById(_engineId);
    if (spec == null) {
      return SpeechStartResult(
        success: false,
        message: 'Selected offline speech engine is not configured.',
      );
    }

    final requestedLocale = _normalizeLocale(localeId);
    final resolved = await _resolveInstalledPackForLocale(
      spec,
      requestedLocale,
    );
    if (resolved == null) {
      final missingLang =
          requestedLocale.startsWith('en') ? 'English' : 'Hebrew';
      return SpeechStartResult(
        success: false,
        message:
            'Offline model not downloaded yet. Open Settings > Speech '
            'recognition host and download the $missingLang pack for '
            '${spec.shortLabel}.',
      );
    }

    final gen = ++_sessionGeneration;
    _audioCapture.stop();
    _listening = false;

    try {
      final devices = await refreshAudioInputDevices();
      if (gen != _sessionGeneration) {
        return SpeechStartResult(success: false, message: 'Cancelled.');
      }
      if (devices.isEmpty) {
        return SpeechStartResult(
          success: false,
          message: 'No Windows microphone was found.',
        );
      }

      await _ensureWorkerStarted();
      if (gen != _sessionGeneration) {
        return SpeechStartResult(success: false, message: 'Cancelled.');
      }

      onDiagnostic?.call(
        '[Offline ${spec.shortLabel}] Loading ${resolved.paths.pack.displayName}...',
      );
      final configResponse = await _configureWorkerPack(
        resolved.paths,
        resolved.actualLocale,
      );
      if (gen != _sessionGeneration) {
        return SpeechStartResult(success: false, message: 'Cancelled.');
      }
      if (configResponse['ok'] != true) {
        final err = configResponse['error']?.toString() ?? 'Unknown load error';
        return SpeechStartResult(
          success: false,
          message: 'Could not load offline model: $err',
        );
      }

      final loadMs = configResponse['loadMs'];
      final cached = configResponse['cached'] == true;
      final decodingMode =
          configResponse['decodingMode']?.toString() ?? 'greedy_search';
      final hotwordCount = (configResponse['hotwordCount'] as int?) ?? 0;
      final boostDesc =
          hotwordCount > 0
              ? '$decodingMode + $hotwordCount script hotwords'
              : decodingMode;
      onDiagnostic?.call(
        cached
            ? '[Offline ${spec.shortLabel}] Ready (warm cache, locale=${resolved.actualLocale}, $boostDesc)'
            : '[Offline ${spec.shortLabel}] Loaded in ${loadMs ?? 0} ms (locale=${resolved.actualLocale}, $boostDesc)',
      );

      _activeLocale = resolved.actualLocale;
      _audioCapture.start(
        preferredDeviceId: _preferredDeviceId,
        preferredLabel: _preferredDeviceLabel,
        onSamples: (samples, rmsLevel) => _onAudioChunk(gen, samples, rmsLevel),
      );

      _listening = true;
      onStatusChange?.call(SpeechStatus.listening);

      final fallbackMissingLang =
          resolved.usedFallbackLanguage
              ? SpeechStartResult.languageNameFromLocale(requestedLocale)
              : null;
      return SpeechStartResult(
        success: true,
        actualLocale: resolved.actualLocale,
        languageMissing: resolved.usedFallbackLanguage,
        missingLanguageName: fallbackMissingLang,
      );
    } catch (error) {
      _audioCapture.stop();
      _listening = false;
      return SpeechStartResult(
        success: false,
        message: 'Offline speech recognition failed to start: $error',
      );
    }
  }

  @override
  void setLocale(String locale) {
    if (!_listening) return;
    final normalized = _normalizeLocale(locale);
    if (normalized == _activeLocale) return;

    final spec = OfflineSttModelCatalog.engineById(_engineId);
    if (spec == null) return;

    final gen = _sessionGeneration;
    unawaited(_switchLocaleAsync(gen, spec, normalized));
  }

  Future<void> _switchLocaleAsync(
    int generation,
    OfflineSttEngineSpec spec,
    String targetLocale,
  ) async {
    final targetPack = spec.packForLocale(targetLocale);
    final resolvedPaths = await _modelManager.resolveInstalledPack(targetPack);
    if (!_listening || generation != _sessionGeneration) return;

    if (resolvedPaths == null) {
      onDiagnostic?.call(
        '[Offline ${spec.shortLabel}] ${targetPack.languageLabel} pack not '
        'downloaded; staying on $_activeLocale.',
      );
      onStatusChange?.call(SpeechStatus.listening);
      return;
    }

    try {
      final response = await _configureWorkerPack(resolvedPaths, targetLocale);
      if (!_listening || generation != _sessionGeneration) return;
      if (response['ok'] == true) {
        _activeLocale = targetLocale;
        final cached = response['cached'] == true;
        onDiagnostic?.call(
          cached
              ? '[Offline ${spec.shortLabel}] Switched to $targetLocale (instant)'
              : '[Offline ${spec.shortLabel}] Switched to $targetLocale '
                  '(${response['loadMs'] ?? 0} ms)',
        );
      } else {
        onDiagnostic?.call(
          '[Offline ${spec.shortLabel}] Locale switch failed: '
          '${response['error']}',
        );
      }
      onStatusChange?.call(SpeechStatus.listening);
    } catch (error) {
      if (!_listening || generation != _sessionGeneration) return;
      onDiagnostic?.call(
        '[Offline ${spec.shortLabel}] Locale switch error: $error',
      );
      onStatusChange?.call(SpeechStatus.listening);
    }
  }

  @override
  Future<void> stop() async {
    _sessionGeneration++;
    final wasListening = _listening;
    _listening = false;
    _audioCapture.stop();
    if (_workerSendPort != null) {
      try {
        _workerSendPort!.send({'type': 'flush'});
      } catch (_) {}
    }
    if (wasListening) {
      onSoundLevelChange?.call(0.0);
      onStatusChange?.call(SpeechStatus.idle);
    }
  }

  Future<void> dispose() async {
    await stop();
    final port = _workerSendPort;
    _workerSendPort = null;
    if (port != null) {
      try {
        port.send({'type': 'dispose'});
      } catch (_) {}
    }
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete({'ok': false, 'error': 'Disposed'});
      }
    }
    _pendingRequests.clear();
    await _workerSub?.cancel();
    _workerSub = null;
    _workerReceivePort?.close();
    _workerReceivePort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
  }

  void _onAudioChunk(int generation, Float32List samples, double rmsLevel) {
    if (!_listening || generation != _sessionGeneration) return;

    final now = DateTime.now();
    if (now.difference(_lastSoundLevelEmit).inMilliseconds >= 60) {
      _lastSoundLevelEmit = now;
      onSoundLevelChange?.call(rmsLevel);
    }

    final port = _workerSendPort;
    if (port == null) return;
    final transferable = TransferableTypedData.fromList([
      samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes),
    ]);
    port.send({'type': 'audio', 'samples': transferable});
  }

  Future<void> _ensureWorkerStarted() async {
    if (_workerSendPort != null && _workerIsolate != null) return;

    final receivePort = ReceivePort();
    _workerReceivePort = receivePort;
    final readyCompleter = Completer<SendPort>();

    _workerSub = receivePort.listen((dynamic message) {
      if (message is SendPort) {
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete(message);
        }
        return;
      }
      if (message is! Map<Object?, Object?>) return;
      _handleWorkerMessage(message);
    });

    _workerIsolate = await Isolate.spawn(
      sherpaSttWorkerMain,
      receivePort.sendPort,
      debugName: 'SherpaOfflineSttWorker',
    );
    _workerSendPort = await readyCompleter.future.timeout(
      const Duration(seconds: 10),
    );
  }

  void _handleWorkerMessage(Map<Object?, Object?> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'configured':
        final requestId = msg['requestId'] as int?;
        if (requestId != null) {
          final completer = _pendingRequests.remove(requestId);
          if (completer != null && !completer.isCompleted) {
            completer.complete(msg);
          }
        }
        break;
      case 'result':
        if (!_listening) return;
        final text = (msg['text'] as String? ?? '').trim();
        if (text.isEmpty) return;
        final isFinal = msg['isFinal'] == true;
        final streamId = msg['streamId'] as int?;
        onResult?.call(
          SpeechResult(
            text,
            isFinal,
            isCumulative: true,
            streamId: streamId,
          ),
        );
        break;
      case 'error':
        final message = msg['message']?.toString() ?? 'Offline STT error';
        onDiagnostic?.call('[Offline Sherpa] $message');
        onError?.call(message);
        break;
    }
  }

  Future<Map<Object?, Object?>> _configureWorkerPack(
    OfflineSttResolvedPackPaths resolved,
    String locale,
  ) {
    final port = _workerSendPort;
    if (port == null) {
      return Future.value({'ok': false, 'error': 'Worker not started'});
    }
    final requestId = ++_requestSequence;
    final completer = Completer<Map<Object?, Object?>>();
    _pendingRequests[requestId] = completer;

    port.send({
      'type': 'configure',
      'requestId': requestId,
      'packId': resolved.pack.packId,
      'locale': locale,
      'kind': resolved.pack.recognizerKind.name,
      'encoder': resolved.encoderPath,
      'decoder': resolved.decoderPath,
      'joiner': resolved.joinerPath,
      'tokens': resolved.tokensPath,
      'scriptBoostEnabled': _scriptBoostEnabled,
      'scriptWords': _scriptBoostEnabled ? _scriptWords : const <String>[],
    });

    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        return {'ok': false, 'error': 'Timed out loading offline speech model.'};
      },
    );
  }

  Future<
    ({
      OfflineSttResolvedPackPaths paths,
      String actualLocale,
      bool usedFallbackLanguage,
    })?
  >
  _resolveInstalledPackForLocale(
    OfflineSttEngineSpec spec,
    String requestedLocale,
  ) async {
    final primaryPack = spec.packForLocale(requestedLocale);
    final primaryResolved = await _modelManager.resolveInstalledPack(
      primaryPack,
    );
    if (primaryResolved != null) {
      return (
        paths: primaryResolved,
        actualLocale: requestedLocale,
        usedFallbackLanguage: false,
      );
    }

    final alternatePack = spec.alternatePackForLocale(requestedLocale);
    final alternateResolved = await _modelManager.resolveInstalledPack(
      alternatePack,
    );
    if (alternateResolved != null) {
      final actualLocale = alternatePack.languageCode == 'en' ? 'en_US' : 'he_IL';
      return (
        paths: alternateResolved,
        actualLocale: actualLocale,
        usedFallbackLanguage: true,
      );
    }

    return null;
  }

  String _normalizeLocale(String? localeId) {
    final value = (localeId ?? '').trim().toLowerCase();
    if (value.startsWith('en')) return 'en_US';
    return 'he_IL';
  }
}
