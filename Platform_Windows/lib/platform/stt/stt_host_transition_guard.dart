/// Owns one browser-host transition at a time and prevents stale async work
/// from releasing or replacing a newer transition.
class SttHostTransitionGuard {
  int _generation = 0;
  int? _activeLease;

  bool get isActive => _activeLease != null;

  int begin() {
    final lease = ++_generation;
    _activeLease = lease;
    return lease;
  }

  bool owns(int lease) => _activeLease == lease;

  bool release(int lease) {
    if (!owns(lease)) return false;
    _activeLease = null;
    return true;
  }

  void invalidate() {
    _generation++;
    _activeLease = null;
  }
}
