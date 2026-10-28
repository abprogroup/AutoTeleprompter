/// Bounded retries for transient connection failures, never a busy loop.
class ConnectionRetryGate {
  int _failures = 0;
  DateTime? _retryAt;
  bool _blocked = false;

  bool canAttempt(DateTime now) =>
      !_blocked && (_retryAt == null || !now.isBefore(_retryAt!));

  void succeeded() {
    _failures = 0;
    _retryAt = null;
    _blocked = false;
  }

  void failed(DateTime now, {bool requiresSignIn = false}) {
    _blocked = requiresSignIn;
    _failures = (_failures + 1).clamp(1, 5);
    final seconds = (30 * (1 << (_failures - 1))).clamp(30, 300);
    _retryAt = now.add(Duration(seconds: seconds));
  }
}
