import 'dart:async';

/// One non-overlapping pass on startup/resume and every 30s while open.
/// The owning services decide whether expiry/backoff actually needs network I/O.
class ConnectionMaintenance {
  ConnectionMaintenance(
    this.checks, {
    this.interval = const Duration(seconds: 30),
  });
  final List<Future<void> Function()> checks;
  final Duration interval;
  Timer? _timer;
  Future<void>? _pending;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  Future<void> checkNow() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final operation = Future.wait(
      checks.map((check) async {
        try {
          await check();
        } catch (_) {
          // Each service reports its own safe state. One cannot block the other.
        }
      }),
    ).then<void>((_) {});
    _pending = operation;
    operation.then((_) {
      if (identical(_pending, operation)) _pending = null;
    });
    return operation;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
