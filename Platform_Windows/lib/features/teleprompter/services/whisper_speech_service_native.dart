import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'speech_service.dart';
import 'whisper_audio_signal.dart';
import 'whisper_input_device_resolver.dart';
import 'whisper_model_support.dart';
import 'whisper_native_process_gate.dart';
import 'whisper_phrase_session_coordinator.dart';

export 'whisper_model_support.dart';

part 'whisper_speech_service_native.models.dart';

const int _modelMarkerSchema = 1;
const String _bundledTinyModelAsset = 'assets/models/ggml-tiny.bin';
const String _tinyModelSha256 =
    'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21';

class WhisperSpeechService {
  static const _startupTimeout = Duration(seconds: 60);
  static const _ioTimeout = Duration(seconds: 30);
  static const _shortStopTimeout = Duration(seconds: 3);
  static const _nativeStopTimeout = Duration(seconds: 10);
  static const _nativeLeaseTimeout = Duration(seconds: 30);
  final AudioRecorder _recorder = AudioRecorder();
  final WhisperAudioSignalTracker _audioSignal = WhisperAudioSignalTracker();
  final WhisperPcmFrameNormalizer _audioFrames = WhisperPcmFrameNormalizer();
  final WhisperBoundedAudioFeed _audioFeed = WhisperBoundedAudioFeed();

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;
  void Function(String)? onDiagnostic;
  void Function(double)? onSoundLevelChange;

  WhisperModel _activeModel = WhisperModel.tiny;
  WhisperPhraseSessionCoordinator? _nativeCoordinator;
  Object? _nativeLeaseOwner;
  StreamSubscription<Uint8List>? _audioSubscription;
  Future<Stream<Uint8List>>? _pendingRecorderStart;
  Future<bool>? _recorderStopInFlight;
  Future<void>? _shutdownInFlight;
  HttpClient? _downloadClient;
  int _sessionGeneration = 0;
  int _downloadGeneration = 0;
  bool _downloadInProgress = false;
  bool _recorderStarted = false;
  bool _starting = false;
  bool _isListening = false;
  bool _disposed = false;
  bool _nativePoisoned = false;
  bool _capturePoisoned = false;
  String _lastTranscript = '';
  String _committedTranscript = '';
  String _activePhraseTranscript = '';
  String _lastObservedTranscript = '';
  String _preferredInputDeviceLabel = 'System default microphone';

  bool get isListening => _isListening;

  void setPreferredInputDeviceLabel(String? label) {
    final normalized = label?.trim() ?? '';
    _preferredInputDeviceLabel =
        normalized.isEmpty ? 'System default microphone' : normalized;
  }

  Future<WhisperModelReadiness> modelReadiness(WhisperModel model) =>
      _modelReadiness(model);

  Future<bool> isModelDownloaded(WhisperModel model) =>
      _isModelDownloaded(model);

  Future<bool> downloadModel({
    required WhisperModel model,
    void Function(String status)? onProgress,
  }) => _downloadModel(model: model, onProgress: onProgress);

  void cancelModelDownload() => _cancelModelDownload();

  Future<bool> initialize({
    required WhisperModel model,
    void Function(String)? onProgress,
  }) => _prepareModel(model, onProgress: onProgress);

  Future<void> start({String? localeId, WhisperModel? model}) async {
    if (_disposed) return;
    if (_nativePoisoned || _capturePoisoned) {
      _emitStartFailure(
        'Offline speech needs an app restart after an incomplete audio-engine shutdown.',
      );
      return;
    }
    await _endSession(SpeechStatus.idle, notify: false);
    if (_disposed) return;
    if (_nativePoisoned || _capturePoisoned) {
      _emitStartFailure(
        'Offline speech needs an app restart after an incomplete audio-engine shutdown.',
      );
      return;
    }
    if (_pendingRecorderStart != null) {
      _emitStartFailure(
        'Whisper init failed: the previous microphone session is still closing.',
      );
      return;
    }

    final generation = ++_sessionGeneration;
    final selectedModel = model ?? _activeModel;
    _starting = true;
    _lastTranscript = '';
    _committedTranscript = '';
    _activePhraseTranscript = '';
    _lastObservedTranscript = '';

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

      final inputDevice = await resolveWhisperInputDevice(
        recorder: _recorder,
        preferredLabel: _preferredInputDeviceLabel,
        onDiagnostic: onDiagnostic,
      );
      if (!_isCurrent(generation)) return;

      final files = await _modelFiles(selectedModel);
      final coordinator = WhisperPhraseSessionCoordinator(
        streamFactory:
            () async => GgmlWhisperNativeStream(
              await startWhisperLiveSession(
                modelPath: files.model.path,
                lang: whisperLanguageForLocale(localeId),
                suppressNonSpeechTokens: false,
                keepModelLoaded: true,
                threads: Platform.numberOfProcessors.clamp(2, 8).toInt(),
                gateRmsMin: whisperNativeGateRmsMin,
                gateVoiceRatio: whisperNativeGateVoiceRatio,
                gateNoiseFloorCap: whisperNativeGateNoiseFloorCap,
              ),
            ),
        onPartial:
            (transcript) => _handleNativePhraseTranscript(
              generation,
              transcript,
              isFinal: false,
            ),
        onPhraseFinal:
            (transcript) => _handleNativePhraseTranscript(
              generation,
              transcript,
              isFinal: true,
            ),
        onFailure: () => _handleSessionFailure(generation),
        startTimeout: _startupTimeout,
        stopTimeout: _nativeStopTimeout,
      );
      final leaseOwner = Object();
      _nativeLeaseOwner = leaseOwner;
      final leaseAcquired = await whisperNativeProcessGate.acquire(
        leaseOwner,
        timeout: _nativeLeaseTimeout,
      );
      if (!_isCurrent(generation)) {
        if (identical(_nativeLeaseOwner, leaseOwner)) {
          _nativeLeaseOwner = null;
        }
        if (leaseAcquired) {
          whisperNativeProcessGate.release(leaseOwner, clean: true);
        }
        return;
      }
      if (!leaseAcquired) {
        if (identical(_nativeLeaseOwner, leaseOwner)) {
          _nativeLeaseOwner = null;
        }
        _nativePoisoned = _nativePoisoned || whisperNativeProcessGate.poisoned;
        await _failStart(
          generation,
          _nativePoisoned
              ? 'Whisper needs an app restart after an incomplete previous shutdown.'
              : 'Whisper init failed: the previous offline engine is still closing.',
        );
        return;
      }
      // Publish ownership before awaiting native start so a concurrent stop can
      // retire this exact stream and no older service can stop a newer owner.
      _nativeCoordinator = coordinator;
      if (!await coordinator.start()) {
        _nativePoisoned = _nativePoisoned || coordinator.poisoned;
        await _failStart(
          generation,
          'Whisper init failed: the offline engine could not start.',
        );
        return;
      }
      if (!_isCurrent(generation)) {
        final shutdown = _shutdownInFlight;
        if (shutdown != null) await shutdown;
        return;
      }

      final recorderStart = _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          device: inputDevice,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      _pendingRecorderStart = recorderStart;
      _cleanUpLateRecorderStart(recorderStart, generation);
      final audioStream = await recorderStart.timeout(_ioTimeout);
      if (identical(_pendingRecorderStart, recorderStart)) {
        _pendingRecorderStart = null;
      }
      _recorderStarted = true;
      if (!_isCurrent(generation)) {
        await _stopRecorder();
        return;
      }

      _activeModel = selectedModel;
      _starting = false;
      _isListening = true;
      _audioSignal.reset();
      _audioFrames.reset();
      _audioFeed.reset();
      _audioSubscription = audioStream.listen(
        (bytes) {
          if (!_isCurrent(generation) || !_isListening) return;
          for (final frame in _audioFrames.add(bytes)) {
            final signal = _audioSignal.add(frame);
            if (signal.shouldEmitMeter) {
              _emitSoundLevel(signal.meterLevel);
            }
            final wasFeeding = _audioFeed.isFeeding;
            for (final payload in _audioFeed.add(
              frame,
              speechActive: signal.speechEvidenceActive,
            )) {
              coordinator.feed(payload);
            }
            if (wasFeeding && !_audioFeed.isFeeding) {
              coordinator.closePhrase();
            }
          }
        },
        onError: (_) => _handleAudioFailure(generation),
        onDone: () => _handleAudioFailure(generation),
        cancelOnError: true,
      );
      _emitStatus(SpeechStatus.listening);
    } on TimeoutException {
      // Future.timeout cannot cancel microphone capture. Refuse an in-process
      // restart so a late capture cannot overlap a newer session.
      if (_pendingRecorderStart != null) {
        _capturePoisoned = true;
      } else {
        _nativePoisoned = true;
      }
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
    await _ignoreErrors(_recorder.dispose(), timeout: _shortStopTimeout);
    // Model state is process-global too. Acquire a maintenance lease before
    // releasing it so a replacement provider cannot start a stream under us.
    final maintenanceLease = Object();
    if (!_nativePoisoned &&
        await whisperNativeProcessGate.acquire(
          maintenanceLease,
          timeout: _nativeStopTimeout,
        )) {
      var clean = false;
      try {
        await WhisperController().releaseModel().timeout(_nativeStopTimeout);
        clean = true;
      } catch (_) {
        _nativePoisoned = true;
      } finally {
        whisperNativeProcessGate.release(maintenanceLease, clean: clean);
      }
    }
  }

  void _handleNativePhraseTranscript(
    int generation,
    String transcript, {
    required bool isFinal,
  }) {
    if (!_isCurrent(generation) || !_isListening) return;
    final phrase = normalizeWhisperTranscript(transcript);
    if (phrase.isNotEmpty) _activePhraseTranscript = phrase;
    final settledPhrase =
        isFinal && phrase.isEmpty ? _activePhraseTranscript : phrase;
    if (isFinal && settledPhrase.isEmpty) {
      _activePhraseTranscript = '';
      return;
    }
    final combined = _joinWhisperTranscript(
      _committedTranscript,
      settledPhrase,
    );
    final observationChanged = combined != _lastObservedTranscript;
    _lastObservedTranscript = combined;
    if (!isFinal && !observationChanged) return;

    final normalized = acceptedWhisperPartial(
      transcript: combined,
      previousTranscript: _lastTranscript,
      // A phrase-final callback is produced only by an acknowledged native
      // stop requested after app-level speech evidence closed.
      acceptsTranscripts: isFinal || _audioSignal.acceptsTranscripts,
      allowDuplicate: isFinal,
    );
    if (isFinal) {
      _committedTranscript = combined;
      _activePhraseTranscript = '';
    }
    if (normalized != null) {
      _lastTranscript = normalized;
      try {
        onResult?.call(SpeechResult(normalized, isFinal));
      } catch (_) {}
    }
  }

  static String _joinWhisperTranscript(String prefix, String suffix) {
    if (prefix.isEmpty) return suffix;
    if (suffix.isEmpty) return prefix;
    return '$prefix $suffix';
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

  Future<void> _endSession(SpeechStatus status, {bool notify = true}) async {
    _sessionGeneration++;
    final cancelStartupDownload = _starting;
    _starting = false;
    _isListening = false;
    _emitSoundLevel(0.0);
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
    final coordinator = _nativeCoordinator;
    final leaseOwner = _nativeLeaseOwner;
    _audioSubscription = null;
    _nativeCoordinator = null;
    _nativeLeaseOwner = null;
    _lastTranscript = '';
    _committedTranscript = '';
    _activePhraseTranscript = '';
    _lastObservedTranscript = '';

    var cleanNativeShutdown = coordinator == null;
    var cleanCaptureShutdown = false;
    try {
      if (audioSubscription != null) {
        await _ignoreErrors(
          audioSubscription.cancel(),
          timeout: _shortStopTimeout,
        );
      }
      // The provider has already closed presentation, so the stop-finalized
      // text is intentionally discarded instead of moving the teleprompter.
      _audioFeed.finish();
      _audioFrames.reset();
      _audioFeed.reset();
      _audioSignal.reset();
      cleanCaptureShutdown = await _stopRecorder();
      if (coordinator != null) {
        try {
          cleanNativeShutdown = await coordinator.stop();
        } catch (_) {
          cleanNativeShutdown = false;
        }
        _nativePoisoned =
            _nativePoisoned || coordinator.poisoned || !cleanNativeShutdown;
      }
    } finally {
      if (leaseOwner != null) {
        whisperNativeProcessGate.release(
          leaseOwner,
          clean:
              cleanNativeShutdown &&
              coordinator?.poisoned != true &&
              cleanCaptureShutdown &&
              !_capturePoisoned &&
              !_nativePoisoned,
        );
      }
    }
  }

  Future<bool> _stopRecorder() async {
    final existing = _recorderStopInFlight;
    if (existing != null) return existing;
    final operation = _performStopRecorder();
    _recorderStopInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_recorderStopInFlight, operation)) {
        _recorderStopInFlight = null;
      }
    }
  }

  Future<bool> _performStopRecorder() async {
    final pendingStart = _pendingRecorderStart;
    if (!_recorderStarted && pendingStart != null) {
      try {
        await pendingStart.timeout(_shortStopTimeout);
        _recorderStarted = true;
      } on TimeoutException {
        _capturePoisoned = true;
        return false;
      } catch (_) {
        return true;
      }
    }
    if (!_recorderStarted) return true;
    try {
      await _recorder.stop().timeout(_shortStopTimeout);
      _recorderStarted = false;
      return true;
    } catch (_) {
      // A timed-out native recorder stop may still complete later. Refuse to
      // start a second capture in this process and overlap microphone streams.
      _capturePoisoned = true;
      return false;
    }
  }

  void _cleanUpLateRecorderStart(
    Future<Stream<Uint8List>> recorderStart,
    int generation,
  ) {
    unawaited(
      recorderStart
          .then<void>((_) async {
            if (!_isCurrent(generation)) {
              _recorderStarted = true;
              await _stopRecorder();
            }
          }, onError: (_) {})
          .whenComplete(() {
            if (identical(_pendingRecorderStart, recorderStart)) {
              _pendingRecorderStart = null;
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

  void _emitSoundLevel(double level) {
    if (_disposed) return;
    try {
      onSoundLevelChange?.call(level.clamp(0.0, 1.0).toDouble());
    } catch (_) {}
  }

  static void _safeProgress(void Function(String)? callback, String message) {
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
}
