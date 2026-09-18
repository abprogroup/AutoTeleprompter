import 'dart:async';

final WhisperNativeProcessGate whisperNativeProcessGate =
    WhisperNativeProcessGate();

/// Owns whisper_ggml's process-global streaming state across service instances.
///
/// A provider can be disposed without awaiting its stop future. The next
/// provider must therefore wait for the previous native stream to acknowledge
/// shutdown before it calls the package's global stream-start API.
class WhisperNativeProcessGate {
  Object? _owner;
  Completer<void>? _released;
  bool _poisoned = false;

  bool get poisoned => _poisoned;

  Future<bool> acquire(Object owner, {required Duration timeout}) async {
    if (identical(_owner, owner)) return !_poisoned;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (_poisoned) return false;
      if (_owner == null) {
        _owner = owner;
        _released = Completer<void>();
        return true;
      }

      final signal = _released;
      final remaining = deadline.difference(DateTime.now());
      if (signal == null || remaining <= Duration.zero) return false;
      try {
        await signal.future.timeout(remaining);
      } on TimeoutException {
        return false;
      }
    }
  }

  void release(Object owner, {required bool clean}) {
    if (!identical(_owner, owner)) return;
    if (!clean) _poisoned = true;
    _owner = null;
    final signal = _released;
    _released = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }
}
