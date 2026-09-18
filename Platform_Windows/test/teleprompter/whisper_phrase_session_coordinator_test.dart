import 'dart:async';
import 'dart:typed_data';

import 'package:autoteleprompter/features/teleprompter/services/whisper_phrase_session_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'finalizes a phrase and drains handoff audio into a clean stream',
    () async {
      final first = _FakeNativeStream();
      final second = _FakeNativeStream()..completeStop('');
      final streams = <_FakeNativeStream>[first, second];
      final finals = <String>[];
      var factoryIndex = 0;
      final coordinator = WhisperPhraseSessionCoordinator(
        streamFactory: () async => streams[factoryIndex++],
        onPartial: (_) {},
        onPhraseFinal: finals.add,
        onFailure: () => fail('unexpected coordinator failure'),
        startTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(seconds: 1),
      );

      expect(await coordinator.start(), isTrue);
      coordinator.feed(Uint8List.fromList([1, 2]));
      coordinator.closePhrase();
      await _waitUntil(() => first.stopRequested);
      coordinator.feed(Uint8List.fromList([3, 4]));
      expect(coordinator.queuedAudioBytes, 2);

      first.completeStop('שלום עולם');
      await _waitUntil(() => second.fed.isNotEmpty);

      expect(finals, ['שלום עולם']);
      expect(first.fed.single, [1, 2]);
      expect(second.fed.single, [3, 4]);
      expect(coordinator.queuedAudioBytes, 0);
      expect(await coordinator.stop(), isTrue);
    },
  );

  test(
    'preserves every queued phrase boundary during a slow handoff',
    () async {
      final first = _FakeNativeStream();
      final second = _FakeNativeStream();
      final third = _FakeNativeStream();
      final fourth = _FakeNativeStream()..completeStop('');
      final streams = <_FakeNativeStream>[first, second, third, fourth];
      final finals = <String>[];
      var factoryIndex = 0;
      final coordinator = WhisperPhraseSessionCoordinator(
        streamFactory: () async => streams[factoryIndex++],
        onPartial: (_) {},
        onPhraseFinal: finals.add,
        onFailure: () => fail('unexpected coordinator failure'),
      );

      expect(await coordinator.start(), isTrue);
      coordinator.closePhrase();
      await _waitUntil(() => first.stopRequested);
      coordinator.feed(Uint8List.fromList([2, 2]));
      coordinator.closePhrase();
      coordinator.feed(Uint8List.fromList([3, 3]));
      coordinator.closePhrase();
      coordinator.feed(Uint8List.fromList([4, 4]));

      first.completeStop('one');
      await _waitUntil(() => second.stopRequested);
      expect(second.fed, [
        [2, 2],
      ]);
      expect(third.fed, isEmpty);

      second.completeStop('two');
      await _waitUntil(() => third.stopRequested);
      expect(third.fed, [
        [3, 3],
      ]);
      expect(fourth.fed, isEmpty);

      third.completeStop('three');
      await _waitUntil(() => fourth.fed.isNotEmpty);

      expect(fourth.fed, [
        [4, 4],
      ]);
      expect(finals, ['one', 'two', 'three']);
      expect(await coordinator.stop(), isTrue);
    },
  );

  test(
    'poisons instead of silently dropping queued speech on overflow',
    () async {
      final first = _FakeNativeStream();
      var failures = 0;
      var factoryCalls = 0;
      final coordinator = WhisperPhraseSessionCoordinator(
        streamFactory: () async {
          factoryCalls++;
          return first;
        },
        onPartial: (_) {},
        onPhraseFinal: (_) {},
        onFailure: () => failures++,
        maxQueuedAudioBytes: 4,
        stopTimeout: const Duration(seconds: 1),
      );

      expect(await coordinator.start(), isTrue);
      coordinator.closePhrase();
      await _waitUntil(() => first.stopRequested);
      coordinator.feed(Uint8List.fromList([1, 1]));
      coordinator.feed(Uint8List.fromList([2, 2]));
      expect(coordinator.queuedAudioBytes, 4);

      coordinator.feed(Uint8List.fromList([3, 3]));

      expect(failures, 1);
      expect(coordinator.poisoned, isTrue);
      expect(coordinator.queuedAudioBytes, 0);
      expect(factoryCalls, 1);
      first.completeStop('first');
      expect(await coordinator.stop(), isFalse);
    },
  );

  test('ignores an error from a stream already retiring', () async {
    final first = _FakeNativeStream();
    final second = _FakeNativeStream()..completeStop('');
    final streams = <_FakeNativeStream>[first, second];
    var factoryIndex = 0;
    var failures = 0;
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () async => streams[factoryIndex++],
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () => failures++,
      stopTimeout: const Duration(seconds: 1),
    );

    expect(await coordinator.start(), isTrue);
    coordinator.closePhrase();
    await _waitUntil(() => first.stopRequested);

    first.emitError(StateError('retired stream error'));
    await Future<void>.delayed(Duration.zero);
    expect(failures, 0);
    expect(coordinator.poisoned, isFalse);

    first.completeStop('first');
    await _waitUntil(() => factoryIndex == 2);
    expect(await coordinator.stop(), isTrue);
  });

  test('poisons restart when native phrase stop never acknowledges', () async {
    final first = _FakeNativeStream();
    var failures = 0;
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () async => first,
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () => failures++,
      startTimeout: const Duration(milliseconds: 100),
      stopTimeout: const Duration(milliseconds: 20),
    );

    expect(await coordinator.start(), isTrue);
    coordinator.closePhrase();
    await _waitUntil(() => coordinator.poisoned);

    expect(failures, 1);
    expect(coordinator.poisoned, isTrue);
    expect(await coordinator.stop(), isFalse);
  });

  test('retires a stream that resolves during stop exactly once', () async {
    final pendingStart = Completer<WhisperNativeStream>();
    final late = _FakeNativeStream()..completeStop('late');
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () => pendingStart.future,
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () {},
      startTimeout: const Duration(seconds: 1),
      stopTimeout: const Duration(seconds: 1),
    );

    final starting = coordinator.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = coordinator.stop();
    pendingStart.complete(late);

    expect(await starting, isFalse);
    expect(await stopping, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(late.stopCalls, 1);
  });

  test('preserves every phrase boundary during a slow handoff', () async {
    final first = _FakeNativeStream();
    final second = _FakeNativeStream();
    final third = _FakeNativeStream()..completeStop('');
    final streams = <_FakeNativeStream>[first, second, third];
    final finals = <String>[];
    var factoryIndex = 0;
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () async => streams[factoryIndex++],
      onPartial: (_) {},
      onPhraseFinal: finals.add,
      onFailure: () => fail('unexpected coordinator failure'),
      startTimeout: const Duration(seconds: 1),
      stopTimeout: const Duration(seconds: 1),
    );

    expect(await coordinator.start(), isTrue);
    coordinator.feed(Uint8List.fromList([1]));
    coordinator.closePhrase();
    await _waitUntil(() => first.stopRequested);

    coordinator.feed(Uint8List.fromList([2]));
    coordinator.closePhrase();
    coordinator.feed(Uint8List.fromList([3]));
    first.completeStop('first');

    await _waitUntil(() => second.stopRequested);
    expect(second.fed, [
      [2],
    ]);
    second.completeStop('second');
    await _waitUntil(() => third.fed.isNotEmpty);

    expect(finals, ['first', 'second']);
    expect(third.fed, [
      [3],
    ]);
    expect(await coordinator.stop(), isTrue);
  });

  test('poisons and reports a native feed failure exactly once', () async {
    final stream = _FakeNativeStream(throwOnFeed: true)..completeStop('');
    var failures = 0;
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () async => stream,
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () => failures++,
    );

    expect(await coordinator.start(), isTrue);
    coordinator.feed(Uint8List.fromList([1, 2]));
    coordinator.feed(Uint8List.fromList([3, 4]));

    expect(coordinator.poisoned, isTrue);
    expect(failures, 1);
    expect(await coordinator.stop(), isFalse);
  });

  test('retires a stream whose partial listener cannot attach', () async {
    final stream = _FakeNativeStream(throwOnListen: true)..completeStop('');
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () async => stream,
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () {},
    );

    expect(await coordinator.start(), isFalse);
    expect(stream.stopCalls, 1);
  });

  test('contains a synchronous native factory failure', () async {
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () => throw StateError('factory failed'),
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () {},
    );

    expect(await coordinator.start(), isFalse);
  });

  test('bounds stop latency while retiring a late restart once', () async {
    final first = _FakeNativeStream();
    final pendingRestart = Completer<WhisperNativeStream>();
    var factoryCalls = 0;
    final coordinator = WhisperPhraseSessionCoordinator(
      streamFactory: () {
        factoryCalls++;
        return factoryCalls == 1
            ? Future<WhisperNativeStream>.value(first)
            : pendingRestart.future;
      },
      onPartial: (_) {},
      onPhraseFinal: (_) {},
      onFailure: () {},
      startTimeout: const Duration(seconds: 2),
      stopTimeout: const Duration(milliseconds: 30),
    );

    expect(await coordinator.start(), isTrue);
    coordinator.closePhrase();
    await _waitUntil(() => first.stopRequested);
    first.completeStop('first');
    await _waitUntil(() => factoryCalls == 2);

    final stopwatch = Stopwatch()..start();
    expect(await coordinator.stop(), isFalse);
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));

    final late = _FakeNativeStream()..completeStop('');
    pendingRestart.complete(late);
    await _waitUntil(() => late.stopCalls == 1);
    expect(late.stopCalls, 1);
  });
}

class _FakeNativeStream implements WhisperNativeStream {
  _FakeNativeStream({this.throwOnFeed = false, this.throwOnListen = false});

  final StreamController<String> _partials = StreamController<String>();
  final Completer<String> _stop = Completer<String>();
  final List<List<int>> fed = <List<int>>[];
  final bool throwOnFeed;
  final bool throwOnListen;
  bool stopRequested = false;
  int stopCalls = 0;

  @override
  Stream<String> get partials =>
      throwOnListen ? const _ThrowingListenStream() : _partials.stream;

  @override
  void feed(Uint8List pcm16Bytes) {
    if (throwOnFeed) throw StateError('feed failed');
    fed.add(pcm16Bytes.toList());
  }

  @override
  Future<String> stop() {
    stopRequested = true;
    stopCalls++;
    return _stop.future;
  }

  void completeStop(String transcript) {
    if (!_stop.isCompleted) _stop.complete(transcript);
  }

  void emitError(Object error) {
    if (!_partials.isClosed) _partials.addError(error);
  }
}

class _ThrowingListenStream extends Stream<String> {
  const _ThrowingListenStream();

  @override
  StreamSubscription<String> listen(
    void Function(String event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => throw StateError('listen failed');
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
