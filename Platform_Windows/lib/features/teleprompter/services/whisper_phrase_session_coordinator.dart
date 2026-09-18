import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:whisper_ggml/whisper_ggml.dart';

abstract interface class WhisperNativeStream {
  Stream<String> get partials;

  void feed(Uint8List pcm16Bytes);

  Future<String> stop();
}

class GgmlWhisperNativeStream implements WhisperNativeStream {
  const GgmlWhisperNativeStream(this._session);

  final WhisperLiveSession _session;

  @override
  Stream<String> get partials => _session.partials;

  @override
  void feed(Uint8List pcm16Bytes) => _session.feed(pcm16Bytes);

  @override
  Future<String> stop() => _session.stop();
}

typedef WhisperNativeStreamFactory = Future<WhisperNativeStream> Function();

sealed class _QueuedPhraseEvent {
  const _QueuedPhraseEvent();
}

final class _QueuedAudio extends _QueuedPhraseEvent {
  const _QueuedAudio(this.bytes);

  final Uint8List bytes;
}

final class _QueuedPhraseBoundary extends _QueuedPhraseEvent {
  const _QueuedPhraseBoundary();
}

const _queuedPhraseBoundary = _QueuedPhraseBoundary();

/// Serializes phrase-finalization around whisper_ggml's process-global stream.
///
/// The native API has no acknowledged flush operation. Ending a phrase with
/// [WhisperNativeStream.stop] both finalizes its short tail and clears native
/// PCM state. The model remains parked by the configured factory, so the next
/// phrase starts without loading the model again. Audio arriving during the
/// handoff is retained in a bounded FIFO instead of reaching a stale stream.
class WhisperPhraseSessionCoordinator {
  WhisperPhraseSessionCoordinator({
    required WhisperNativeStreamFactory streamFactory,
    required void Function(String transcript) onPartial,
    required void Function(String transcript) onPhraseFinal,
    required void Function() onFailure,
    Duration startTimeout = const Duration(seconds: 60),
    Duration stopTimeout = const Duration(seconds: 10),
    int maxQueuedAudioBytes = 16000 * 2 * 5,
  }) : _streamFactory = streamFactory,
       _onPartial = onPartial,
       _onPhraseFinal = onPhraseFinal,
       _onFailure = onFailure,
       _startTimeout = startTimeout,
       _stopTimeout = stopTimeout,
       _maxQueuedAudioBytes = maxQueuedAudioBytes;

  final WhisperNativeStreamFactory _streamFactory;
  final void Function(String transcript) _onPartial;
  final void Function(String transcript) _onPhraseFinal;
  final void Function() _onFailure;
  final Duration _startTimeout;
  final Duration _stopTimeout;
  final int _maxQueuedAudioBytes;

  final ListQueue<_QueuedPhraseEvent> _queuedEvents =
      ListQueue<_QueuedPhraseEvent>();
  final Map<WhisperNativeStream, Future<({bool success, String transcript})>>
  _stopOperations =
      HashMap<
        WhisperNativeStream,
        Future<({bool success, String transcript})>
      >.identity();
  final Expando<bool> _retiredStreams = Expando<bool>(
    'retired whisper streams',
  );
  WhisperNativeStream? _stream;
  StreamSubscription<String>? _partialSubscription;
  Future<WhisperNativeStream>? _pendingStart;
  Future<void>? _rotationInFlight;
  int _queuedAudioBytes = 0;
  int _generation = 0;
  bool _active = false;
  bool _rotating = false;
  bool _poisoned = false;
  bool _failureNotified = false;

  bool get poisoned => _poisoned;
  bool get isRotating => _rotating;
  int get queuedAudioBytes => _queuedAudioBytes;

  Future<bool> start() async {
    if (_poisoned || _active) return false;
    _active = true;
    final generation = ++_generation;
    final started = await _startStream(generation);
    if (!started) _active = false;
    return started;
  }

  void feed(Uint8List pcm16Bytes) {
    if (!_active || _poisoned || pcm16Bytes.isEmpty) return;
    final stream = _stream;
    if (_rotating || stream == null) {
      _queueAudio(pcm16Bytes);
      return;
    }
    try {
      stream.feed(pcm16Bytes);
    } catch (_) {
      _fail();
    }
  }

  void closePhrase() {
    if (!_active || _poisoned) return;
    if (_rotating) {
      _queuedEvents.addLast(_queuedPhraseBoundary);
      return;
    }

    _rotating = true;
    final generation = _generation;
    late final Future<void> rotation;
    rotation = _rotate(generation).whenComplete(() {
      if (identical(_rotationInFlight, rotation)) {
        _rotationInFlight = null;
      }
      _rotating = false;
      if (_active && !_poisoned && _consumeLeadingBoundary()) {
        closePhrase();
      }
    });
    _rotationInFlight = rotation;
  }

  Future<bool> stop() async {
    _active = false;
    _generation++;

    final rotation = _rotationInFlight;
    var rotationTimedOut = false;
    if (rotation != null) {
      try {
        await rotation.timeout(_stopTimeout);
      } catch (_) {
        _poisoned = true;
        rotationTimedOut = true;
      }
    }

    final pending = _pendingStart;
    if (!rotationTimedOut && _stream == null && pending != null) {
      try {
        final lateStream = await pending.timeout(_stopTimeout);
        await _stopStream(lateStream);
      } catch (_) {
        _poisoned = true;
      }
    }

    final subscription = _partialSubscription;
    final stream = _stream;
    _partialSubscription = null;
    _stream = null;
    _clearQueuedEvents();
    if (subscription != null) {
      try {
        await subscription.cancel().timeout(_stopTimeout);
      } catch (_) {}
    }
    if (stream != null) await _stopStream(stream);
    return !_poisoned;
  }

  Future<void> _rotate(int generation) async {
    try {
      final stream = _stream;
      final subscription = _partialSubscription;
      _stream = null;
      _partialSubscription = null;
      if (stream == null) {
        _fail();
        return;
      }

      final stopped = await _stopStream(stream);
      if (subscription != null) {
        try {
          await subscription.cancel().timeout(_stopTimeout);
        } catch (_) {}
      }
      if (!stopped.success) {
        _fail();
        return;
      }
      if (!_active || generation != _generation) return;

      _safeTranscriptCallback(_onPhraseFinal, stopped.transcript);
      if (!await _startStream(generation)) _fail();
    } catch (_) {
      _fail();
    }
  }

  Future<bool> _startStream(int generation) async {
    late final Future<WhisperNativeStream> pending;
    try {
      pending = _streamFactory();
    } catch (_) {
      return false;
    }
    _pendingStart = pending;
    _cleanUpLateStart(pending, generation);

    late final WhisperNativeStream stream;
    try {
      stream = await pending.timeout(_startTimeout);
    } on TimeoutException {
      _poisoned = true;
      return false;
    } catch (_) {
      return false;
    } finally {
      if (identical(_pendingStart, pending)) _pendingStart = null;
    }

    if (!_active || generation != _generation || _poisoned) {
      await _stopStream(stream);
      return false;
    }

    _stream = stream;
    try {
      _partialSubscription = stream.partials.listen(
        (transcript) {
          if (_active &&
              generation == _generation &&
              identical(_stream, stream)) {
            _safeTranscriptCallback(_onPartial, transcript);
          }
        },
        onError: (_) {
          if (_active &&
              generation == _generation &&
              identical(_stream, stream)) {
            _fail();
          }
        },
        onDone: () {
          if (_active &&
              generation == _generation &&
              identical(_stream, stream)) {
            _fail();
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      _stream = null;
      await _stopStream(stream);
      return false;
    }
    _drainQueuedAudio(stream);
    return true;
  }

  void _cleanUpLateStart(Future<WhisperNativeStream> pending, int generation) {
    unawaited(
      pending.then<void>((stream) async {
        if (!_active || generation != _generation || _poisoned) {
          await _stopStream(stream);
        }
      }, onError: (_) {}),
    );
  }

  Future<({bool success, String transcript})> _stopStream(
    WhisperNativeStream stream,
  ) {
    final existing = _stopOperations[stream];
    if (existing != null) return existing;
    if (_retiredStreams[stream] == true) {
      return Future.value((success: true, transcript: ''));
    }

    late final Future<({bool success, String transcript})> operation;
    operation = _performStopStream(stream).whenComplete(() {
      _retiredStreams[stream] = true;
      if (identical(_stopOperations[stream], operation)) {
        _stopOperations.remove(stream);
      }
    });
    _stopOperations[stream] = operation;
    return operation;
  }

  Future<({bool success, String transcript})> _performStopStream(
    WhisperNativeStream stream,
  ) async {
    try {
      final transcript = await stream.stop().timeout(_stopTimeout);
      return (success: true, transcript: transcript);
    } catch (_) {
      _poisoned = true;
      return (success: false, transcript: '');
    }
  }

  void _queueAudio(Uint8List pcm16Bytes) {
    final copy = Uint8List.fromList(pcm16Bytes);
    if (_queuedAudioBytes + copy.length > _maxQueuedAudioBytes) {
      _clearQueuedEvents();
      _fail();
      return;
    }
    _queuedEvents.addLast(_QueuedAudio(copy));
    _queuedAudioBytes += copy.length;
  }

  void _drainQueuedAudio(WhisperNativeStream stream) {
    while (_queuedEvents.isNotEmpty &&
        _active &&
        !_poisoned &&
        identical(_stream, stream)) {
      final event = _queuedEvents.first;
      if (event is _QueuedPhraseBoundary) return;
      final audio = _queuedEvents.removeFirst() as _QueuedAudio;
      _queuedAudioBytes -= audio.bytes.length;
      try {
        stream.feed(audio.bytes);
      } catch (_) {
        _fail();
        return;
      }
    }
  }

  bool _consumeLeadingBoundary() {
    if (_queuedEvents.isEmpty ||
        _queuedEvents.first is! _QueuedPhraseBoundary) {
      return false;
    }
    _queuedEvents.removeFirst();
    return true;
  }

  void _clearQueuedEvents() {
    _queuedEvents.clear();
    _queuedAudioBytes = 0;
  }

  void _fail() {
    if (_failureNotified || !_active) return;
    _failureNotified = true;
    _poisoned = true;
    _active = false;
    try {
      _onFailure();
    } catch (_) {}
  }

  static void _safeTranscriptCallback(
    void Function(String transcript) callback,
    String transcript,
  ) {
    try {
      callback(transcript);
    } catch (_) {}
  }
}
