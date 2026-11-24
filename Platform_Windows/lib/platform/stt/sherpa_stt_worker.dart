import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'offline_stt_model_catalog.dart';
import 'sherpa_hotwords_builder.dart';
import 'sherpa_stt_models.dart';
import 'sherpa_transcript_emitter.dart';

/// Background isolate entry point for running `sherpa_onnx` speech recognition
/// completely off the Flutter UI thread.
void sherpaSttWorkerMain(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  final runner = _SherpaWorkerRunner(mainPort);
  receivePort.listen((dynamic message) {
    if (message is! Map<Object?, Object?>) return;
    final type = message['type'] as String?;
    switch (type) {
      case 'configure':
        runner.handleConfigure(message);
        break;
      case 'audio':
        runner.handleAudio(message);
        break;
      case 'flush':
        runner.handleFlush();
        break;
      case 'dispose':
        runner.dispose();
        receivePort.close();
        Isolate.exit();
    }
  });
}

class _SherpaWorkerRunner {
  _SherpaWorkerRunner(this._mainPort);

  static const int _sampleRate = SherpaModelFactory.sampleRate;
  // Rolling buffer limits for OfflineRecognizer (Parakeet TDT 0.6B).
  // Keep window compact (7.5 s) and stride gentle (550 ms) so CPU & iGPU
  // stay completely free for 60/120+ fps teleprompter scrolling.
  static const int _offlinePreRollSamples = (_sampleRate * 500) ~/ 1000;
  static const int _offlineMaxUtteranceSamples = (_sampleRate * 7500) ~/ 1000;
  static const int _offlineRollOverlapSamples = (_sampleRate * 2000) ~/ 1000;
  static const int _offlineMinDecodeSamples = (_sampleRate * 450) ~/ 1000;
  static const int _offlineMinNewSamplesPerDecode = (_sampleRate * 500) ~/ 1000;
  static const int _offlineBasePartialIntervalMs = 550;
  static const int _offlineSilenceFinalizeMs = 2000;
  static const double _offlineSpeechRmsThreshold = 0.004;
  static const double _offlineSpeechPeakThreshold = 0.018;

  final SendPort _mainPort;
  bool _bindingsInitialized = false;

  // Cache parsed tokens.txt vocabularies so hotwords build in < 2 ms.
  final Map<String, SherpaTokenVocab> _vocabCache = {};

  // Keep up to 2 lightweight online recognizers (HE + EN) warm for instant switching.
  final Map<String, LoadedSherpaOnlineModel> _onlineCache = {};
  LoadedSherpaOnlineModel? _activeOnline;

  // Keep only 1 heavy offline recognizer (~650 MB) in RAM at a time.
  LoadedSherpaOfflineModel? _activeOffline;

  String? _activeCacheKey;
  String? _activeLocale;
  int _utteranceStreamId = 1;
  final SherpaTranscriptEmitter _emitter = SherpaTranscriptEmitter();

  // Rolling speech state for offline models (Parakeet TDT).
  final List<double> _offlinePreRoll = [];
  final List<double> _offlineSamples = [];
  bool _offlineHasSpeech = false;
  int _offlineSilenceMs = 0;
  int _offlineLastDecodeAtMs = 0;
  int _offlineLastDecodeDurationMs = 0;
  int _offlineSamplesSinceDecode = 0;

  void _ensureBindings() {
    if (_bindingsInitialized) return;
    sherpa_onnx.initBindings();
    _bindingsInitialized = true;
  }

  SherpaHotwordsResult _buildHotwords({
    required String tokensPath,
    required bool scriptBoostEnabled,
    required List<String> scriptWords,
    required String locale,
  }) {
    if (!scriptBoostEnabled || scriptWords.isEmpty) {
      return const SherpaHotwordsResult(text: '', wordCount: 0);
    }
    var vocab = _vocabCache[tokensPath];
    if (vocab == null) {
      vocab = SherpaTokenVocab.fromFile(tokensPath);
      if (vocab != null) {
        _vocabCache[tokensPath] = vocab;
      }
    }
    if (vocab == null) {
      return const SherpaHotwordsResult(text: '', wordCount: 0);
    }
    return SherpaHotwordsBuilder.buildForVocab(
      vocab: vocab,
      words: scriptWords,
      locale: locale,
    );
  }

  void handleConfigure(Map<Object?, Object?> msg) {
    final requestId = msg['requestId'] as int? ?? 0;
    final packId = msg['packId'] as String? ?? '';
    final locale = msg['locale'] as String? ?? 'he_IL';
    final kindName = msg['kind'] as String? ?? '';
    final encoder = msg['encoder'] as String? ?? '';
    final decoder = msg['decoder'] as String? ?? '';
    final joiner = msg['joiner'] as String? ?? '';
    final tokens = msg['tokens'] as String? ?? '';
    final scriptBoostEnabled = msg['scriptBoostEnabled'] == true;
    final rawWords = msg['scriptWords'] as List<Object?>? ?? const [];
    final scriptWords = rawWords.whereType<String>().toList(growable: false);

    try {
      _ensureBindings();
      final kind =
          kindName == OfflineSttRecognizerKind.offlineNemoTransducer.name
              ? OfflineSttRecognizerKind.offlineNemoTransducer
              : kindName == OfflineSttRecognizerKind.onlineNemoCtc.name
              ? OfflineSttRecognizerKind.onlineNemoCtc
              : OfflineSttRecognizerKind.onlineZipformer2;
      final isOnline =
          kind == OfflineSttRecognizerKind.onlineZipformer2 ||
          kind == OfflineSttRecognizerKind.onlineNemoCtc;
      final hotwords = _buildHotwords(
        tokensPath: tokens,
        scriptBoostEnabled:
            scriptBoostEnabled && kind != OfflineSttRecognizerKind.onlineNemoCtc,
        scriptWords: scriptWords,
        locale: locale,
      );
      final hotwordsSig =
          scriptBoostEnabled ? hotwords.text.hashCode : 0;

      if (isOnline) {
        final cacheKey = '$packId|boost=$scriptBoostEnabled';
        final sw = Stopwatch()..start();
        _releaseOffline();
        var loaded = _onlineCache[cacheKey];
        var cached = loaded != null;

        if (loaded == null) {
          if (_onlineCache.length >= 2) {
            final oldestKey = _onlineCache.keys.first;
            _onlineCache.remove(oldestKey)?.dispose();
          }
          loaded =
              kind == OfflineSttRecognizerKind.onlineNemoCtc
                  ? SherpaModelFactory.createOnlineNemoCtcModel(
                    cacheKey: cacheKey,
                    modelPath: encoder,
                    tokens: tokens,
                  )
                  : SherpaModelFactory.createOnlineZipformerModel(
                    cacheKey: cacheKey,
                    encoder: encoder,
                    decoder: decoder,
                    joiner: joiner,
                    tokens: tokens,
                    scriptBoostEnabled: scriptBoostEnabled,
                    hotwordsText: hotwords.text,
                  );
          _onlineCache[cacheKey] = loaded;
        } else {
          loaded.recreateStream(hotwords: hotwords.text);
        }

        sw.stop();
        _activeOnline = loaded;
        _activeCacheKey = cacheKey;
        _activeLocale = locale;
        _resetOfflineBuffer(clearPreRoll: true);
        _advanceUtterance();

        _mainPort.send({
          'type': 'configured',
          'requestId': requestId,
          'ok': true,
          'packId': packId,
          'locale': locale,
          'loadMs': sw.elapsedMilliseconds,
          'cached': cached,
          'decodingMode': loaded.decodingMode,
          'hotwordCount':
              loaded.activeHotwords.isEmpty ? 0 : hotwords.wordCount,
        });
        return;
      }

      // OfflineRecognizer (Parakeet TDT 0.6B): hotwords are bound to recognizer
      // config, so include the hotwords signature in the cache key.
      final cacheKey = '$packId|boost=$scriptBoostEnabled|hw=$hotwordsSig';
      if (_activeCacheKey == cacheKey && _activeOffline != null) {
        _activeLocale = locale;
        _resetActiveUtterance();
        _mainPort.send({
          'type': 'configured',
          'requestId': requestId,
          'ok': true,
          'packId': packId,
          'locale': locale,
          'cached': true,
          'decodingMode': _activeOffline!.decodingMode,
          'hotwordCount': _activeOffline!.hotwordCount,
        });
        return;
      }

      final sw = Stopwatch()..start();
      _releaseAllOnline();
      _releaseOffline();
      final offline = SherpaModelFactory.createOfflineNemoTransducerModel(
        cacheKey: cacheKey,
        packId: packId,
        encoder: encoder,
        decoder: decoder,
        joiner: joiner,
        tokens: tokens,
        scriptBoostEnabled: scriptBoostEnabled,
        hotwords: hotwords,
      );
      sw.stop();

      _activeOffline = offline;
      _activeCacheKey = cacheKey;
      _activeLocale = locale;
      _resetActiveUtterance();

      _mainPort.send({
        'type': 'configured',
        'requestId': requestId,
        'ok': true,
        'packId': packId,
        'locale': locale,
        'loadMs': sw.elapsedMilliseconds,
        'cached': false,
        'decodingMode': offline.decodingMode,
        'hotwordCount': offline.hotwordCount,
      });
    } catch (error) {
      _mainPort.send({
        'type': 'configured',
        'requestId': requestId,
        'ok': false,
        'error': error.toString(),
      });
    }
  }

  void handleAudio(Map<Object?, Object?> msg) {
    final transferable = msg['samples'] as TransferableTypedData?;
    if (transferable == null) return;
    final bytes = transferable.materialize();
    final samples = bytes.asFloat32List();
    if (samples.isEmpty) return;

    if (_activeOnline != null) {
      _processOnlineSamples(samples);
    } else if (_activeOffline != null) {
      _processOfflineSamples(samples);
    }
  }

  void handleFlush() {
    if (_activeOnline != null) {
      final online = _activeOnline!;
      final text = _cleanTranscript(
        online.recognizer.getResult(online.stream).text,
      );
      if (text.isNotEmpty) {
        _emitTranscript(text, isFinal: true);
      }
      online.recreateStream();
      _advanceUtterance();
      return;
    }

    if (_activeOffline != null &&
        _offlineHasSpeech &&
        _offlineSamples.length >= _offlineMinDecodeSamples) {
      _decodeOfflineBuffer(isFinal: true);
    }
    _resetOfflineBuffer(clearPreRoll: true);
  }

  void _processOnlineSamples(Float32List samples) {
    final online = _activeOnline!;
    online.stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
    while (online.recognizer.isReady(online.stream)) {
      online.recognizer.decode(online.stream);
    }

    final rawText = _cleanTranscript(
      online.recognizer.getResult(online.stream).text,
    );
    final endpoint = online.recognizer.isEndpoint(online.stream);

    if (endpoint) {
      if (rawText.isNotEmpty) {
        _emitTranscript(rawText, isFinal: true);
      }
      online.recreateStream();
      _advanceUtterance();
      return;
    }

    if (rawText.isNotEmpty) {
      _emitTranscript(rawText, isFinal: false);
    }
  }

  void _processOfflineSamples(Float32List samples) {
    final chunkMs = (samples.length * 1000 / _sampleRate).round();
    var sumSq = 0.0;
    var peak = 0.0;
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      sumSq += s * s;
      final absVal = s.abs();
      if (absVal > peak) peak = absVal;
    }
    final rms = math.sqrt(sumSq / samples.length);
    final isSpeechChunk =
        rms >= _offlineSpeechRmsThreshold ||
        peak >= _offlineSpeechPeakThreshold;

    if (!_offlineHasSpeech) {
      _appendToPreRoll(samples);
      if (!isSpeechChunk) return;
      _offlineHasSpeech = true;
      _offlineSilenceMs = 0;
      _offlineSamples.addAll(_offlinePreRoll);
      _offlinePreRoll.clear();
      _offlineSamplesSinceDecode = _offlineSamples.length;
    } else {
      if (isSpeechChunk) {
        _offlineSilenceMs = 0;
      } else {
        _offlineSilenceMs += chunkMs;
      }
      for (var i = 0; i < samples.length; i++) {
        _offlineSamples.add(samples[i]);
      }
      _offlineSamplesSinceDecode += samples.length;
    }

    final reachedMaxWindow =
        _offlineSamples.length >= _offlineMaxUtteranceSamples;
    final reachedSilenceEndpoint =
        _offlineSilenceMs >= _offlineSilenceFinalizeMs;

    if (reachedSilenceEndpoint) {
      if (_offlineSamples.length >= _offlineMinDecodeSamples) {
        _decodeOfflineBuffer(isFinal: true);
      }
      _resetOfflineBuffer(clearPreRoll: false);
      _advanceUtterance();
      return;
    }

    if (reachedMaxWindow) {
      _decodeOfflineBuffer(isFinal: true);
      final keepStart = math.max(
        0,
        _offlineSamples.length - _offlineRollOverlapSamples,
      );
      final overlap = _offlineSamples.sublist(keepStart);
      _offlineSamples
        ..clear()
        ..addAll(overlap);
      _offlineSamplesSinceDecode = 0;
      _offlineSilenceMs = 0;
      _advanceUtterance();
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final minIntervalMs = math.max(
      _offlineBasePartialIntervalMs,
      _offlineLastDecodeDurationMs + 80,
    );
    final dueForPartial =
        _offlineSamples.length >= _offlineMinDecodeSamples &&
        _offlineSamplesSinceDecode >= _offlineMinNewSamplesPerDecode &&
        nowMs - _offlineLastDecodeAtMs >= minIntervalMs;
    if (dueForPartial) {
      _decodeOfflineBuffer(isFinal: false);
    }
  }

  void _appendToPreRoll(Float32List samples) {
    for (var i = 0; i < samples.length; i++) {
      _offlinePreRoll.add(samples[i]);
    }
    if (_offlinePreRoll.length > _offlinePreRollSamples) {
      _offlinePreRoll.removeRange(
        0,
        _offlinePreRoll.length - _offlinePreRollSamples,
      );
    }
  }

  void _decodeOfflineBuffer({required bool isFinal}) {
    final offline = _activeOffline;
    if (offline == null || _offlineSamples.isEmpty) return;

    final audio = Float32List(_offlineSamples.length);
    for (var i = 0; i < _offlineSamples.length; i++) {
      audio[i] = _offlineSamples[i];
    }

    final sw = Stopwatch()..start();
    final stream = offline.recognizer.createStream();
    try {
      stream.acceptWaveform(samples: audio, sampleRate: _sampleRate);
      offline.recognizer.decode(stream);
      final text = _cleanTranscript(offline.recognizer.getResult(stream).text);
      sw.stop();
      _offlineLastDecodeDurationMs = sw.elapsedMilliseconds;
      _offlineLastDecodeAtMs = DateTime.now().millisecondsSinceEpoch;
      _offlineSamplesSinceDecode = 0;
      if (text.isNotEmpty) {
        _emitTranscript(text, isFinal: isFinal);
      }
    } catch (error) {
      _mainPort.send({
        'type': 'error',
        'message': 'Offline decode failed: $error',
      });
    } finally {
      stream.free();
    }
  }

  void _emitTranscript(String text, {required bool isFinal}) {
    final emission = _emitter.prepareEmission(text, forceFinal: isFinal);
    if (emission == null) return;
    _mainPort.send({
      'type': 'result',
      'text': emission.text,
      'isFinal': emission.isFinal,
      'streamId': _utteranceStreamId,
      'locale': _activeLocale ?? 'he_IL',
    });
  }

  void _resetActiveUtterance() {
    _resetOfflineBuffer(clearPreRoll: true);
    if (_activeOnline != null) {
      _activeOnline!.recreateStream();
    }
    _advanceUtterance();
  }

  void _advanceUtterance() {
    _utteranceStreamId++;
    _emitter.reset();
  }

  void _resetOfflineBuffer({required bool clearPreRoll}) {
    _offlineSamples.clear();
    if (clearPreRoll) {
      _offlinePreRoll.clear();
    }
    _offlineHasSpeech = false;
    _offlineSilenceMs = 0;
    _offlineSamplesSinceDecode = 0;
  }

  String _cleanTranscript(String raw) {
    return raw
        .replaceAll(RegExp(r'[\u0591-\u05C7]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _releaseAllOnline() {
    for (final entry in _onlineCache.values) {
      entry.dispose();
    }
    _onlineCache.clear();
    _activeOnline = null;
  }

  void _releaseOffline() {
    _activeOffline?.dispose();
    _activeOffline = null;
  }

  void dispose() {
    _releaseAllOnline();
    _releaseOffline();
    _resetOfflineBuffer(clearPreRoll: true);
  }
}
