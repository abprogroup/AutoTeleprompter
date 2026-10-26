/// Bounded debug counters, not speech evidence or a restart policy.
class SttResultFlowDiagnostics {
  int _received = 0;
  int _filtered = 0;
  int _reported = 0;
  DateTime? _lastResult;
  bool _idleReported = false;

  void record({required bool filtered, required DateTime now}) {
    _received++;
    if (filtered) _filtered++;
    _lastResult = now;
    _idleReported = false;
  }

  void reset() {
    _received = _filtered = _reported = 0;
    _lastResult = null;
    _idleReported = false;
  }

  String? takeSummary(DateTime now) {
    final last = _lastResult;
    if (last == null) return null;
    final age = now.difference(last).inSeconds.clamp(0, 86400);
    if (_reported == _received && (age < 15 || _idleReported)) return null;
    _reported = _received;
    if (age >= 15) _idleReported = true;
    return '[Speech input] received=$_received eligible=${_received - _filtered} '
        'filtered=$_filtered lastResultAge=${age}s '
        '(filtered=empty/consumed; silence or provider delay not distinguished)';
  }
}
