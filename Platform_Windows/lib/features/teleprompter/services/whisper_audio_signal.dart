import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

const double whisperNativeGateRmsMin = 0.008;
const double whisperNativeGateVoiceRatio = 1.35;
const double whisperNativeGateNoiseFloorCap = 0.007;

double whisperNativeGateThreshold(double noiseFloor) => math.max(
  whisperNativeGateRmsMin,
  math.min(noiseFloor, whisperNativeGateNoiseFloorCap) *
      whisperNativeGateVoiceRatio,
);

/// Reframes arbitrary microphone callbacks into deterministic 20 ms PCM16
/// packets before they reach whisper_ggml's callback-scoped native gate.
class WhisperPcmFrameNormalizer {
  static const int frameBytes = 16000 * 20 ~/ 1000 * 2;

  final Uint8List _frame = Uint8List(frameBytes);
  int _filled = 0;

  List<Uint8List> add(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    final output = <Uint8List>[];
    var offset = 0;
    while (offset < chunk.length) {
      final available = frameBytes - _filled;
      final remaining = chunk.length - offset;
      final copied = math.min(available, remaining);
      _frame.setRange(_filled, _filled + copied, chunk, offset);
      _filled += copied;
      offset += copied;

      if (_filled == frameBytes) {
        output.add(Uint8List.fromList(_frame));
        _filled = 0;
      }
    }
    return output;
  }

  Uint8List? takePaddedFrame() {
    if (_filled == 0) return null;
    final output = Uint8List(frameBytes);
    output.setRange(0, _filled, _frame);
    _filled = 0;
    return output;
  }

  void reset() {
    _filled = 0;
  }
}

/// Keeps idle microphone audio out of whisper_ggml's unacknowledged mailbox.
///
/// A bounded pre-roll preserves the beginning of an utterance while the
/// evidence tracker opens. Phrase finalization is owned by the acknowledged
/// native session stop/restart boundary; synthetic silence is never injected.
/// Long quiet periods retain only the pre-roll and send nothing.
class WhisperBoundedAudioFeed {
  static const int _preRollFrames = 25; // 500 ms at 20 ms per frame.

  final ListQueue<Uint8List> _preRoll = ListQueue<Uint8List>();
  bool _feeding = false;
  bool _wasSpeechActive = false;

  int get bufferedPreRollFrames => _preRoll.length;
  bool get isFeeding => _feeding;

  List<Uint8List> add(Uint8List frame, {required bool speechActive}) {
    if (frame.length != WhisperPcmFrameNormalizer.frameBytes) {
      throw ArgumentError.value(
        frame.length,
        'frame.length',
        'Expected one normalized 20 ms PCM16 frame.',
      );
    }

    if (!_feeding) {
      _preRoll.addLast(Uint8List.fromList(frame));
      while (_preRoll.length > _preRollFrames) {
        _preRoll.removeFirst();
      }
      if (!speechActive) return const <Uint8List>[];

      _feeding = true;
      _wasSpeechActive = true;
      final output = _preRoll.toList(growable: false);
      _preRoll.clear();
      return output;
    }

    final output = <Uint8List>[frame];
    if (_wasSpeechActive && !speechActive) {
      _feeding = false;
      _preRoll.clear();
    }
    _wasSpeechActive = speechActive;
    return output;
  }

  List<Uint8List> finish() {
    reset();
    return const <Uint8List>[];
  }

  void reset() {
    _preRoll.clear();
    _feeding = false;
    _wasSpeechActive = false;
  }
}

class WhisperAudioSignalFrame {
  const WhisperAudioSignalFrame({
    required this.rms,
    required this.peak,
    required this.meterLevel,
    required this.shouldEmitMeter,
    required this.speechEvidenceActive,
  });

  final double rms;
  final double peak;
  final double meterLevel;
  final bool shouldEmitMeter;
  final bool speechEvidenceActive;
}

/// Computes a bounded UI meter from PCM16 microphone audio.
///
/// This tracker drives both the visible meter and the bounded upstream audio
/// feed, so quiet room tone cannot grow the native decoder buffer indefinitely.
class WhisperAudioSignalTracker {
  static const int _sampleRate = 16000;
  static const int _meterIntervalSamples = _sampleRate ~/ 10;
  static const int _speechFrameSamples = _sampleRate * 20 ~/ 1000;
  static const int _startupCalibrationSamples = _sampleRate * 300 ~/ 1000;
  static const int _speechAttackSamples = _sampleRate * 200 ~/ 1000;
  static const int _speechReleaseSamples = _sampleRate * 500 ~/ 1000;
  static const int _transcriptGraceSamples = _sampleRate * 2;
  static const int _voiceVariationWindowFrames = 6;
  static const double _minimumNoiseFloor = 0.0045;
  static const double _maximumNoiseFloor = 0.02;
  static const double _speechThresholdNoiseFloorCap = 0.012;
  static const double _minimumSpeechRms = 0.008;
  static const double _voiceOnRatio = 1.35;
  static const double _minimumVoiceVariation = 0.12;

  int _samplesSinceMeterEmission = 0;
  int? _pendingByte;
  double _meterLevel = 0.0;
  double _speechFrameSum = 0.0;
  double _speechFrameSumSquares = 0.0;
  int _speechFrameSampleCount = 0;
  final ListQueue<double> _recentSpeechRms = ListQueue<double>();
  double _noiseFloor = 0.005;
  int _startupSamplesRemaining = _startupCalibrationSamples;
  int _attackSamples = 0;
  int _releaseSamples = 0;
  int _samplesSinceSpeech = _transcriptGraceSamples + 1;
  bool _speechActive = false;
  bool _hasObservedSpeech = false;

  bool get acceptsTranscripts =>
      _speechActive ||
      (_hasObservedSpeech && _samplesSinceSpeech <= _transcriptGraceSamples);

  bool get hasObservedSpeech => _hasObservedSpeech;

  WhisperAudioSignalFrame add(Uint8List chunk) {
    final pcm = _coalesceEvenPcm(chunk);
    if (pcm.isEmpty) {
      return WhisperAudioSignalFrame(
        rms: 0.0,
        peak: 0.0,
        meterLevel: _meterLevel,
        shouldEmitMeter: false,
        speechEvidenceActive: _speechActive,
      );
    }

    final measurement = _measurePcm16Le(pcm);
    final sampleCount = pcm.length ~/ 2;
    _updateMeter(measurement.rms, sampleCount);
    _updateSpeechEvidencePcm(pcm);
    _samplesSinceMeterEmission += sampleCount;
    final shouldEmitMeter = _samplesSinceMeterEmission >= _meterIntervalSamples;
    if (shouldEmitMeter) {
      _samplesSinceMeterEmission %= _meterIntervalSamples;
    }

    return WhisperAudioSignalFrame(
      rms: measurement.rms,
      peak: measurement.peak,
      meterLevel: _meterLevel,
      shouldEmitMeter: shouldEmitMeter,
      speechEvidenceActive: _speechActive,
    );
  }

  void reset() {
    _samplesSinceMeterEmission = 0;
    _pendingByte = null;
    _meterLevel = 0.0;
    _speechFrameSum = 0.0;
    _speechFrameSumSquares = 0.0;
    _speechFrameSampleCount = 0;
    _recentSpeechRms.clear();
    _noiseFloor = 0.005;
    _startupSamplesRemaining = _startupCalibrationSamples;
    _attackSamples = 0;
    _releaseSamples = 0;
    _samplesSinceSpeech = _transcriptGraceSamples + 1;
    _speechActive = false;
    _hasObservedSpeech = false;
  }

  Uint8List _coalesceEvenPcm(Uint8List chunk) {
    final pending = _pendingByte;
    final combinedLength = chunk.length + (pending == null ? 0 : 1);
    final evenLength = combinedLength - combinedLength.remainder(2);
    if (evenLength == 0) {
      if (chunk.isNotEmpty) _pendingByte = chunk.first;
      return Uint8List(0);
    }

    if (pending == null) {
      if (chunk.length.isOdd) _pendingByte = chunk.last;
      return chunk.length == evenLength
          ? chunk
          : Uint8List.sublistView(chunk, 0, evenLength);
    }

    final output = Uint8List(evenLength)..[0] = pending;
    final bytesFromChunk = evenLength - 1;
    output.setRange(1, evenLength, chunk, 0);
    _pendingByte = bytesFromChunk < chunk.length ? chunk.last : null;
    return output;
  }

  void _updateMeter(double rms, int sampleCount) {
    final target = whisperRmsToMeterLevel(rms);
    final seconds = sampleCount / _sampleRate;
    final timeConstant = target >= _meterLevel ? 0.04 : 0.30;
    final alpha = 1.0 - math.exp(-seconds / timeConstant);
    _meterLevel += alpha * (target - _meterLevel);
    _meterLevel = _meterLevel.clamp(0.0, 1.0).toDouble();
    if (target == 0.0 && _meterLevel < 0.005) {
      _meterLevel = 0.0;
    }
  }

  void _updateSpeechEvidencePcm(Uint8List pcm) {
    for (var offset = 0; offset < pcm.length; offset += 2) {
      final raw = pcm[offset] | (pcm[offset + 1] << 8);
      final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
      final sample = signed / 32768.0;
      _speechFrameSum += sample;
      _speechFrameSumSquares += sample * sample;
      _speechFrameSampleCount++;

      if (_speechFrameSampleCount == _speechFrameSamples) {
        final mean = _speechFrameSum / _speechFrameSampleCount;
        final variance = math.max(
          0.0,
          _speechFrameSumSquares / _speechFrameSampleCount - mean * mean,
        );
        // Removing each frame's DC component prevents biased interfaces and
        // constant electrical offsets from being mistaken for speech energy.
        final rms = math.sqrt(variance);
        _updateSpeechEvidence(rms, _speechFrameSampleCount);
        _speechFrameSum = 0.0;
        _speechFrameSumSquares = 0.0;
        _speechFrameSampleCount = 0;
      }
    }
  }

  void _updateSpeechEvidence(double rms, int sampleCount) {
    _recentSpeechRms.addLast(rms);
    while (_recentSpeechRms.length > _voiceVariationWindowFrames) {
      _recentSpeechRms.removeFirst();
    }

    if (_startupSamplesRemaining > 0) {
      _startupSamplesRemaining = math.max(
        0,
        _startupSamplesRemaining - sampleCount,
      );
      final calibrationRms = rms.clamp(_minimumNoiseFloor, _maximumNoiseFloor);
      _noiseFloor += 0.35 * (calibrationRms - _noiseFloor);
      _noiseFloor =
          _noiseFloor.clamp(_minimumNoiseFloor, _maximumNoiseFloor).toDouble();
      return;
    }

    final thresholdNoiseFloor = math.min(
      _noiseFloor,
      _speechThresholdNoiseFloorCap,
    );
    final onThreshold = math.max(
      _minimumSpeechRms,
      thresholdNoiseFloor * _voiceOnRatio,
    );
    final offThreshold = math.max(
      _minimumSpeechRms * 0.75,
      thresholdNoiseFloor * 1.08,
    );

    if (_speechActive) {
      if (rms >= offThreshold) {
        _releaseSamples = 0;
        _samplesSinceSpeech = 0;
      } else {
        _releaseSamples += sampleCount;
        _samplesSinceSpeech += sampleCount;
        if (_releaseSamples >= _speechReleaseSamples) {
          _speechActive = false;
          _releaseSamples = 0;
        }
      }
      return;
    }

    if (_hasObservedSpeech) {
      _samplesSinceSpeech += sampleCount;
    }

    final recentMin = _recentSpeechRms.reduce(math.min);
    final recentMax = _recentSpeechRms.reduce(math.max);
    final variation =
        recentMax <= 0.0 ? 0.0 : (recentMax - recentMin) / recentMax;
    final voiceLike =
        _recentSpeechRms.length >= 4 && variation >= _minimumVoiceVariation;

    if (rms >= onThreshold && voiceLike) {
      _attackSamples += sampleCount;
      if (_attackSamples >= _speechAttackSamples) {
        _speechActive = true;
        _hasObservedSpeech = true;
        _samplesSinceSpeech = 0;
        _attackSamples = 0;
      }
      return;
    }

    _attackSamples = 0;
    _adaptNoiseFloor(rms, sampleCount);
  }

  void _adaptNoiseFloor(double rms, int sampleCount) {
    final seconds = sampleCount / _sampleRate;
    final timeConstant = rms < _noiseFloor ? 0.35 : 0.55;
    final alpha = 1.0 - math.exp(-seconds / timeConstant);
    _noiseFloor += alpha * (rms - _noiseFloor);
    _noiseFloor =
        _noiseFloor.clamp(_minimumNoiseFloor, _maximumNoiseFloor).toDouble();
  }
}

double whisperRmsToMeterLevel(double rms) {
  if (!rms.isFinite || rms <= 0.0) return 0.0;
  final dbfs = 20.0 * math.log(rms) / math.ln10;
  // Keep ordinary room tone below the visible speech meter while retaining a
  // smooth response for quiet speech. This affects presentation only.
  return ((dbfs + 48.0) / 36.0).clamp(0.0, 1.0).toDouble();
}

String? acceptedWhisperPartial({
  required String transcript,
  required String previousTranscript,
  required bool acceptsTranscripts,
  bool allowDuplicate = false,
}) {
  if (!acceptsTranscripts) return null;
  final normalized = normalizeWhisperTranscript(transcript);
  if (normalized.isEmpty ||
      (!allowDuplicate && normalized == previousTranscript)) {
    return null;
  }
  if (!RegExp(r'[A-Za-z0-9\u05D0-\u05EA]').hasMatch(normalized)) return null;
  return normalized;
}

String normalizeWhisperTranscript(String transcript) {
  final withoutAnnotations = transcript
      .replaceAll(RegExp(r'\[[^\]]{1,80}\]'), '')
      .replaceAll(RegExp(r'\([^\)]{1,80}\)'), '')
      .replaceAll(RegExp(r'<[^>]{1,80}>'), '');
  return withoutAnnotations
      .replaceAll(RegExp(r'[\u266A\u266B]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

({double rms, double peak}) _measurePcm16Le(Uint8List pcm) {
  var sumSquares = 0.0;
  var peak = 0.0;
  final sampleCount = pcm.length ~/ 2;
  for (var offset = 0; offset < sampleCount * 2; offset += 2) {
    final raw = pcm[offset] | (pcm[offset + 1] << 8);
    final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
    final sample = signed / 32768.0;
    final magnitude = sample.abs();
    sumSquares += sample * sample;
    if (magnitude > peak) peak = magnitude;
  }
  return (
    rms: sampleCount == 0 ? 0.0 : math.sqrt(sumSquares / sampleCount),
    peak: peak,
  );
}
