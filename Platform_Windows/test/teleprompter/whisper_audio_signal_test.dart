import 'dart:math' as math;
import 'dart:typed_data';

import 'package:autoteleprompter/features/teleprompter/services/whisper_audio_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Whisper PCM frame normalization', () {
    test('splits a mixed callback into fixed twenty-millisecond frames', () {
      final normalizer = WhisperPcmFrameNormalizer();
      final mixed = Uint8List.fromList([
        ..._constantPcm16(328, 1280),
        ..._constantPcm16(0, 1280),
      ]);

      final frames = normalizer.add(mixed);

      expect(frames, hasLength(8));
      expect(frames.every((frame) => frame.length == 640), isTrue);
      expect(_pcm16Value(frames[0], 0), 328);
      expect(_pcm16Value(frames[3], 319), 328);
      expect(_pcm16Value(frames[4], 0), 0);
      expect(_pcm16Value(frames[7], 319), 0);
    });

    test('produces identical frames for different callback boundaries', () {
      final audio = Uint8List.fromList([
        ..._constantPcm16(328, 1280),
        ..._constantPcm16(0, 1280),
      ]);
      final oneCallback = WhisperPcmFrameNormalizer().add(audio);
      final splitNormalizer = WhisperPcmFrameNormalizer();
      final splitCallbacks = <Uint8List>[
        ...splitNormalizer.add(Uint8List.sublistView(audio, 0, 333)),
        ...splitNormalizer.add(Uint8List.sublistView(audio, 333, 2049)),
        ...splitNormalizer.add(Uint8List.sublistView(audio, 2049)),
      ];

      expect(splitCallbacks, hasLength(oneCallback.length));
      for (var i = 0; i < oneCallback.length; i++) {
        expect(splitCallbacks[i], orderedEquals(oneCallback[i]));
      }
    });

    test('pads only the final partial frame and then clears it', () {
      final normalizer = WhisperPcmFrameNormalizer();
      final partial = _constantPcm16(4000, 100);

      expect(normalizer.add(partial), isEmpty);
      final padded = normalizer.takePaddedFrame();

      expect(padded, isNotNull);
      expect(padded, hasLength(WhisperPcmFrameNormalizer.frameBytes));
      expect(_pcm16Value(padded!, 99), 4000);
      expect(_pcm16Value(padded, 100), 0);
      expect(normalizer.takePaddedFrame(), isNull);
    });
  });

  group('Whisper bounded native feed', () {
    test('keeps long idle audio out of the native session', () {
      final feed = WhisperBoundedAudioFeed();
      final silence = _constantPcm16(0, 320);

      for (var i = 0; i < 500; i++) {
        expect(feed.add(silence, speechActive: false), isEmpty);
      }

      expect(feed.bufferedPreRollFrames, 25);
      expect(feed.isFeeding, isFalse);
      expect(feed.finish(), isEmpty);
      expect(feed.bufferedPreRollFrames, 0);
    });

    test('evicts the oldest pre-roll frames in exact order', () {
      final feed = WhisperBoundedAudioFeed();

      for (var value = 1; value <= 30; value++) {
        feed.add(_constantPcm16(value, 320), speechActive: false);
      }
      final opened = feed.add(_constantPcm16(4000, 320), speechActive: true);

      expect(opened, hasLength(25));
      expect(_pcm16Value(opened.first, 0), 7);
      expect(_pcm16Value(opened[23], 0), 30);
      expect(_pcm16Value(opened.last, 0), 4000);
    });

    test('preserves fixed-frame pre-roll without synthetic decode padding', () {
      final feed = WhisperBoundedAudioFeed();
      final silence = _constantPcm16(0, 320);
      final speech = _constantPcm16(4000, 320);

      for (var i = 0; i < 30; i++) {
        feed.add(silence, speechActive: false);
      }
      final opened = feed.add(speech, speechActive: true);
      final active = feed.add(speech, speechActive: true);
      final closed = feed.add(silence, speechActive: false);

      expect(opened, hasLength(25));
      expect(active, hasLength(1));
      expect(closed, hasLength(1));
      expect(
        [...opened, ...active, closed.first].every(
          (frame) => frame.length == WhisperPcmFrameNormalizer.frameBytes,
        ),
        isTrue,
      );
      expect(_pcm16Value(opened.last, 0), 4000);
      expect(_pcm16Value(closed.first, 0), 0);
      expect(closed.single, hasLength(640));
      expect(feed.isFeeding, isFalse);
      expect(feed.add(silence, speechActive: false), isEmpty);
    });

    test('finish resets without injecting synthetic silence', () {
      final feed = WhisperBoundedAudioFeed();
      final speech = _constantPcm16(4000, 320);

      feed.add(speech, speechActive: true);
      final flush = feed.finish();

      expect(flush, isEmpty);
      expect(feed.isFeeding, isFalse);
      expect(feed.finish(), isEmpty);
    });

    test('rejects non-normalized microphone frames', () {
      final feed = WhisperBoundedAudioFeed();

      expect(
        () => feed.add(Uint8List(639), speechActive: false),
        throwsArgumentError,
      );
      expect(feed.bufferedPreRollFrames, 0);
    });

    test('pipeline output is independent of recorder callback boundaries', () {
      final audio = Uint8List.fromList([
        ..._constantPcm16(0, 4800),
        ..._voicedPcm16(amplitude: 2200, sampleCount: 16000),
        ..._constantPcm16(0, 9600),
      ]);

      final whole = _pipelinePayloads(audio, const []);
      final split = _pipelinePayloads(audio, const [1, 333, 2049, 8193, 16001]);

      expect(split, hasLength(whole.length));
      for (var i = 0; i < whole.length; i++) {
        expect(split[i], orderedEquals(whole[i]));
      }
    });
  });

  group('Whisper PCM16 signal parsing', () {
    test('decodes signed little-endian samples from an offset view', () {
      final backing = Uint8List.fromList(const [
        0xff,
        0x00,
        0x40,
        0x00,
        0xc0,
        0xff,
      ]);
      final view = Uint8List.sublistView(backing, 1, 5);

      final frame = WhisperAudioSignalTracker().add(view);

      expect(frame.rms, closeTo(0.5, 0.000001));
      expect(frame.peak, closeTo(0.5, 0.000001));
    });

    test('carries an odd trailing byte into the next chunk', () {
      final tracker = WhisperAudioSignalTracker();

      final first = tracker.add(Uint8List.fromList(const [0x00]));
      final second = tracker.add(Uint8List.fromList(const [0x40]));

      expect(first.rms, 0.0);
      expect(second.rms, closeTo(0.5, 0.000001));
      expect(second.peak, closeTo(0.5, 0.000001));
    });

    test('reset clears odd-byte, meter, and speech-evidence state', () {
      final tracker = WhisperAudioSignalTracker();
      _openEvidence(tracker);
      expect(tracker.acceptsTranscripts, isTrue);
      tracker.add(Uint8List.fromList(const [0x00]));

      tracker.reset();
      final oddCarryFrame = tracker.add(Uint8List.fromList(const [0x40]));
      final silenceFrame = tracker.add(_constantPcm16(0, 1600));

      expect(oddCarryFrame.rms, 0.0);
      expect(silenceFrame.meterLevel, 0.0);
      expect(tracker.acceptsTranscripts, isFalse);
    });
  });

  group('Whisper audio meter', () {
    test(
      'emits no faster than ten hertz with fast attack and slow release',
      () {
        final tracker = WhisperAudioSignalTracker();
        final loud = _constantPcm16(8192, 800);

        final first = tracker.add(loud);
        final second = tracker.add(loud);
        final third = tracker.add(loud);
        final fourth = tracker.add(loud);
        final afterSilence = tracker.add(_constantPcm16(0, 1600));

        expect(first.shouldEmitMeter, isFalse);
        expect(second.shouldEmitMeter, isTrue);
        expect(third.shouldEmitMeter, isFalse);
        expect(fourth.shouldEmitMeter, isTrue);
        expect(second.meterLevel, greaterThan(0.0));
        expect(fourth.meterLevel, greaterThan(second.meterLevel));
        expect(afterSilence.shouldEmitMeter, isTrue);
        expect(afterSilence.meterLevel, lessThan(fourth.meterLevel));
        expect(afterSilence.meterLevel, greaterThan(0.0));
      },
    );

    test('maps silence, room tone, and invalid RMS safely', () {
      expect(whisperRmsToMeterLevel(0.0), 0.0);
      expect(whisperRmsToMeterLevel(double.nan), 0.0);
      expect(whisperRmsToMeterLevel(0.003), 0.0);
      expect(whisperRmsToMeterLevel(1.0), 1.0);
      expect(
        whisperRmsToMeterLevel(0.01),
        greaterThan(whisperRmsToMeterLevel(0.001)),
      );
    });
  });

  group('Whisper native gate profile', () {
    test('admits quiet speech while rejecting tested room tone', () {
      expect(whisperNativeGateThreshold(0.005), lessThan(0.01001));
      expect(0.01001, greaterThanOrEqualTo(whisperNativeGateThreshold(0.005)));
      expect(0.00701, lessThan(whisperNativeGateThreshold(0.005)));
      expect(0.00701, lessThan(whisperNativeGateThreshold(0.007)));
    });

    test('caps the adaptive floor so louder rooms cannot lock out speech', () {
      expect(
        whisperNativeGateThreshold(0.02),
        whisperNativeGateNoiseFloorCap * whisperNativeGateVoiceRatio,
      );
      expect(whisperNativeGateThreshold(0.02), lessThan(0.01001));
    });
  });

  group('Whisper transcript evidence', () {
    test('does not accept sustained stationary room noise', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(
        tracker,
        _tonePcm16(amplitude: 700, frequencyHz: 60, sampleCount: 16000 * 30),
        chunkSamples: 1600,
      );

      expect(tracker.hasObservedSpeech, isFalse);
      expect(tracker.acceptsTranscripts, isFalse);
    });

    test('does not accept high-gain stationary broadband noise', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(
        tracker,
        _seededNoisePcm16(amplitude: 900, sampleCount: 16000 * 30),
        chunkSamples: 1600,
      );

      expect(tracker.hasObservedSpeech, isFalse);
      expect(tracker.acceptsTranscripts, isFalse);
    });

    test('opens for amplitude-modulated speech after room calibration', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(
        tracker,
        _tonePcm16(amplitude: 180, frequencyHz: 60, sampleCount: 16000 * 3),
        chunkSamples: 1600,
      );
      _feedSignal(
        tracker,
        _voicedPcm16(amplitude: 1600, sampleCount: 16000),
        chunkSamples: 640,
      );

      expect(tracker.hasObservedSpeech, isTrue);
      expect(tracker.acceptsTranscripts, isTrue);
    });

    test('opens when real speech modulation begins during startup', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(
        tracker,
        _voicedPcm16(amplitude: 2200, sampleCount: 16000),
        chunkSamples: 1600,
      );

      expect(tracker.hasObservedSpeech, isTrue);
      expect(tracker.acceptsTranscripts, isTrue);
    });

    test('adapts to a late fan step without opening the evidence gate', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(tracker, _constantPcm16(0, 16000 * 3), chunkSamples: 1600);
      _feedSignal(
        tracker,
        _tonePcm16(amplitude: 900, frequencyHz: 60, sampleCount: 16000 * 8),
        chunkSamples: 1600,
      );
      expect(tracker.acceptsTranscripts, isFalse);

      _feedSignal(
        tracker,
        _voicedPcm16(amplitude: 2600, sampleCount: 16000),
        chunkSamples: 1600,
      );
      expect(tracker.acceptsTranscripts, isTrue);
    });

    test('keeps speech active after high-room-noise calibration', () {
      final tracker = WhisperAudioSignalTracker();
      _feedSignal(
        tracker,
        _seededNoisePcm16(amplitude: 1200, sampleCount: 4800),
        chunkSamples: 640,
      );
      _feedSignal(
        tracker,
        _voicedPcm16(amplitude: 1800, sampleCount: 8000),
        chunkSamples: 640,
      );
      expect(tracker.hasObservedSpeech, isTrue);

      _feedSignal(
        tracker,
        _tonePcm16(amplitude: 850, frequencyHz: 185, sampleCount: 16000 * 3),
        chunkSamples: 640,
      );
      expect(tracker.acceptsTranscripts, isTrue);
    });

    test('rejects a single short click', () {
      final tracker = WhisperAudioSignalTracker();
      tracker.add(_constantPcm16(0, 4800));

      final click = Uint8List(640);
      click[0] = 0xff;
      click[1] = 0x7f;
      tracker.add(click);
      tracker.add(Uint8List(640));

      expect(tracker.hasObservedSpeech, isFalse);
    });

    test('rejects a short click even inside a large callback', () {
      final tracker = WhisperAudioSignalTracker();
      tracker.add(_constantPcm16(0, 4800));
      final clickThenSilence =
          Uint8List(3200)
            ..[0] = 0xff
            ..[1] = 0x7f;

      tracker.add(clickThenSilence);

      expect(tracker.hasObservedSpeech, isFalse);
    });

    test('speech attack is independent of callback size', () {
      final smallChunks = WhisperAudioSignalTracker();
      final largeChunks = WhisperAudioSignalTracker();
      final calibration = _constantPcm16(0, 4800);
      final speech = _voicedPcm16(amplitude: 2200, sampleCount: 16000);
      smallChunks.add(calibration);
      largeChunks.add(calibration);
      _feedSignal(smallChunks, speech, chunkSamples: 320);
      _feedSignal(largeChunks, speech, chunkSamples: 3200);

      expect(smallChunks.acceptsTranscripts, isTrue);
      expect(largeChunks.acceptsTranscripts, isTrue);
    });

    test('room tone closes evidence for every supported callback size', () {
      for (final chunkSamples in <int>[320, 1600, 3200]) {
        final tracker = WhisperAudioSignalTracker();

        _feedSignal(
          tracker,
          _tonePcm16(amplitude: 500, frequencyHz: 60, sampleCount: 16000 * 2),
          chunkSamples: chunkSamples,
        );
        expect(
          tracker.acceptsTranscripts,
          isFalse,
          reason: '$chunkSamples-sample startup room tone',
        );

        _feedSignal(
          tracker,
          _voicedPcm16(amplitude: 2200, sampleCount: 16000),
          chunkSamples: chunkSamples,
        );
        expect(
          tracker.acceptsTranscripts,
          isTrue,
          reason: '$chunkSamples-sample speech',
        );

        _feedSignal(
          tracker,
          _tonePcm16(amplitude: 500, frequencyHz: 60, sampleCount: 16000 * 4),
          chunkSamples: chunkSamples,
        );
        expect(
          tracker.acceptsTranscripts,
          isFalse,
          reason: '$chunkSamples-sample trailing room tone',
        );
      }
    });

    test('keeps a bounded grace period for a delayed final transcript', () {
      final tracker = WhisperAudioSignalTracker();
      _openEvidence(tracker);
      final silence = _constantPcm16(0, 1600);

      for (var i = 0; i < 15; i++) {
        tracker.add(silence);
      }
      expect(tracker.acceptsTranscripts, isTrue);

      for (var i = 0; i < 10; i++) {
        tracker.add(silence);
      }
      expect(tracker.acceptsTranscripts, isFalse);
    });
  });

  group('Whisper partial filtering', () {
    test('rejects transcripts without recent speech evidence', () {
      expect(
        acceptedWhisperPartial(
          transcript: 'invented words',
          previousTranscript: '',
          acceptsTranscripts: false,
        ),
        isNull,
      );
    });

    test('trims and deduplicates real transcripts', () {
      expect(
        acceptedWhisperPartial(
          transcript: '  spoken words  ',
          previousTranscript: '',
          acceptsTranscripts: true,
        ),
        'spoken words',
      );
      expect(
        acceptedWhisperPartial(
          transcript: 'spoken words',
          previousTranscript: 'spoken words',
          acceptsTranscripts: true,
        ),
        isNull,
      );
    });

    test('allows an identical validated phrase-final boundary', () {
      expect(
        acceptedWhisperPartial(
          transcript: 'spoken words',
          previousTranscript: 'spoken words',
          acceptsTranscripts: true,
          allowDuplicate: true,
        ),
        'spoken words',
      );
    });

    test('rejects non-speech-only annotations and musical markers', () {
      for (final transcript in <String>[
        '[BLANK_AUDIO]',
        '[music] ...',
        '(inaudible)',
        '<noise>',
        '♪ ♫',
      ]) {
        expect(
          acceptedWhisperPartial(
            transcript: transcript,
            previousTranscript: '',
            acceptsTranscripts: true,
          ),
          isNull,
          reason: transcript,
        );
      }
    });
  });
}

void _openEvidence(WhisperAudioSignalTracker tracker) {
  tracker.add(_constantPcm16(0, 4800));
  _feedSignal(
    tracker,
    _voicedPcm16(amplitude: 2200, sampleCount: 16000),
    chunkSamples: 1280,
  );
}

void _feedSignal(
  WhisperAudioSignalTracker tracker,
  Uint8List audio, {
  required int chunkSamples,
}) {
  final chunkBytes = chunkSamples * 2;
  for (var offset = 0; offset < audio.length; offset += chunkBytes) {
    final end = math.min(audio.length, offset + chunkBytes);
    tracker.add(Uint8List.sublistView(audio, offset, end));
  }
}

Uint8List _voicedPcm16({required int amplitude, required int sampleCount}) {
  final bytes = Uint8List(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final seconds = i / 16000.0;
    final envelope =
        0.42 + 0.38 * (0.5 + 0.5 * math.sin(2 * math.pi * 6 * seconds));
    final carrier =
        math.sin(2 * math.pi * 185 * seconds) +
        0.32 * math.sin(2 * math.pi * 370 * seconds);
    final value = (amplitude * envelope * carrier).round().clamp(-32768, 32767);
    final encoded = value < 0 ? value + 0x10000 : value;
    bytes[i * 2] = encoded & 0xff;
    bytes[i * 2 + 1] = (encoded >> 8) & 0xff;
  }
  return bytes;
}

Uint8List _tonePcm16({
  required int amplitude,
  required int frequencyHz,
  required int sampleCount,
}) {
  final bytes = Uint8List(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final value =
        (amplitude * math.sin(2 * math.pi * frequencyHz * i / 16000)).round();
    final encoded = value < 0 ? value + 0x10000 : value;
    bytes[i * 2] = encoded & 0xff;
    bytes[i * 2 + 1] = (encoded >> 8) & 0xff;
  }
  return bytes;
}

Uint8List _seededNoisePcm16({
  required int amplitude,
  required int sampleCount,
}) {
  final bytes = Uint8List(sampleCount * 2);
  var state = 0x12345678;
  for (var i = 0; i < sampleCount; i++) {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    final unit = ((state >> 8) & 0xffff) / 32767.5 - 1.0;
    final value = (unit * amplitude).round();
    final encoded = value < 0 ? value + 0x10000 : value;
    bytes[i * 2] = encoded & 0xff;
    bytes[i * 2 + 1] = (encoded >> 8) & 0xff;
  }
  return bytes;
}

Uint8List _constantPcm16(int value, int sampleCount) {
  final bytes = Uint8List(sampleCount * 2);
  final encoded = value < 0 ? value + 0x10000 : value;
  for (var i = 0; i < sampleCount; i++) {
    bytes[i * 2] = encoded & 0xff;
    bytes[i * 2 + 1] = (encoded >> 8) & 0xff;
  }
  return bytes;
}

int _pcm16Value(Uint8List bytes, int sampleIndex) {
  final offset = sampleIndex * 2;
  final raw = bytes[offset] | (bytes[offset + 1] << 8);
  return raw >= 0x8000 ? raw - 0x10000 : raw;
}

List<Uint8List> _pipelinePayloads(Uint8List audio, List<int> cuts) {
  final normalizer = WhisperPcmFrameNormalizer();
  final tracker = WhisperAudioSignalTracker();
  final feed = WhisperBoundedAudioFeed();
  final output = <Uint8List>[];
  var offset = 0;
  for (final requestedCut in [...cuts, audio.length]) {
    final cut = requestedCut.clamp(offset, audio.length).toInt();
    for (final frame in normalizer.add(
      Uint8List.sublistView(audio, offset, cut),
    )) {
      final signal = tracker.add(frame);
      output.addAll(feed.add(frame, speechActive: signal.speechEvidenceActive));
    }
    offset = cut;
  }
  return output;
}
