import 'package:autoteleprompter/features/teleprompter/services/whisper_native_process_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes distinct native-session owners', () async {
    final gate = WhisperNativeProcessGate();
    final first = Object();
    final second = Object();

    expect(
      await gate.acquire(first, timeout: const Duration(seconds: 1)),
      isTrue,
    );
    var secondAcquired = false;
    final waiting = gate
        .acquire(second, timeout: const Duration(seconds: 1))
        .then((value) => secondAcquired = value);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(secondAcquired, isFalse);

    gate.release(first, clean: true);
    expect(await waiting, isTrue);
    gate.release(second, clean: true);
  });

  test('a timed-out waiter never steals the active owner', () async {
    final gate = WhisperNativeProcessGate();
    final first = Object();
    final timedOut = Object();
    final third = Object();

    expect(
      await gate.acquire(first, timeout: const Duration(seconds: 1)),
      isTrue,
    );
    expect(
      await gate.acquire(timedOut, timeout: const Duration(milliseconds: 10)),
      isFalse,
    );
    gate.release(timedOut, clean: true);
    expect(
      await gate.acquire(third, timeout: const Duration(milliseconds: 10)),
      isFalse,
    );

    gate.release(first, clean: true);
    expect(
      await gate.acquire(third, timeout: const Duration(seconds: 1)),
      isTrue,
    );
    gate.release(third, clean: true);
  });

  test(
    'an unclean owner release permanently poisons the process gate',
    () async {
      final gate = WhisperNativeProcessGate();
      final first = Object();

      expect(
        await gate.acquire(first, timeout: const Duration(seconds: 1)),
        isTrue,
      );
      gate.release(first, clean: false);

      expect(gate.poisoned, isTrue);
      expect(
        await gate.acquire(Object(), timeout: const Duration(seconds: 1)),
        isFalse,
      );
    },
  );
}
