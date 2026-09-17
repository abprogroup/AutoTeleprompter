import 'stt_host_policy.dart';
import 'stt_webview2_compatibility.dart';

typedef SttMonotonicElapsedReader = Duration Function();

enum SttHostReadinessPhase {
  serverBound,
  hostLaunched,
  socketConnected,
  microphoneReady,
  recognizerListening,
}

enum SttReadinessAdvanceResult {
  advanced,
  duplicate,
  regressive,
  skipped,
  alreadyComplete,
}

class SttReadinessTimeoutMetadata {
  const SttReadinessTimeoutMetadata({
    required this.awaitingPhase,
    required this.stageElapsed,
    required this.totalElapsed,
    required this.timeout,
  });

  final SttHostReadinessPhase awaitingPhase;
  final Duration stageElapsed;
  final Duration totalElapsed;
  final Duration timeout;

  bool get isTimedOut => stageElapsed >= timeout;
}

/// Enforces the full host-readiness handshake with a monotonic elapsed clock.
class SttHostReadinessStateMachine {
  SttHostReadinessStateMachine({
    Map<SttHostReadinessPhase, Duration>? stageTimeouts,
    SttMonotonicElapsedReader? elapsedReader,
  })  : _stageTimeouts = {
          ...defaultStageTimeouts,
          ...?stageTimeouts,
        },
        _elapsedReader = elapsedReader ?? _stopwatchReader() {
    final startedAt = _now();
    _sessionStartedAt = startedAt;
    _stageStartedAt = startedAt;
  }

  static const Map<SttHostReadinessPhase, Duration> defaultStageTimeouts = {
    SttHostReadinessPhase.serverBound: Duration(seconds: 4),
    SttHostReadinessPhase.hostLaunched: Duration(seconds: 12),
    SttHostReadinessPhase.socketConnected: Duration(seconds: 12),
    SttHostReadinessPhase.microphoneReady: Duration(seconds: 15),
    SttHostReadinessPhase.recognizerListening: Duration(seconds: 12),
  };

  final Map<SttHostReadinessPhase, Duration> _stageTimeouts;
  final SttMonotonicElapsedReader _elapsedReader;

  int _completedIndex = -1;
  Duration _lastElapsed = Duration.zero;
  late Duration _sessionStartedAt;
  late Duration _stageStartedAt;

  SttHostReadinessPhase? get completedPhase => _completedIndex < 0
      ? null
      : SttHostReadinessPhase.values[_completedIndex];

  SttHostReadinessPhase? get awaitingPhase {
    final next = _completedIndex + 1;
    return next >= SttHostReadinessPhase.values.length
        ? null
        : SttHostReadinessPhase.values[next];
  }

  bool get isReady =>
      completedPhase == SttHostReadinessPhase.recognizerListening;

  SttReadinessAdvanceResult advance(SttHostReadinessPhase phase) {
    if (isReady) {
      return phase == completedPhase
          ? SttReadinessAdvanceResult.duplicate
          : SttReadinessAdvanceResult.alreadyComplete;
    }
    if (phase.index == _completedIndex) {
      return SttReadinessAdvanceResult.duplicate;
    }
    if (phase.index < _completedIndex) {
      return SttReadinessAdvanceResult.regressive;
    }
    if (phase.index != _completedIndex + 1) {
      return SttReadinessAdvanceResult.skipped;
    }

    _completedIndex = phase.index;
    _stageStartedAt = _now();
    return SttReadinessAdvanceResult.advanced;
  }

  SttReadinessTimeoutMetadata? timeoutMetadata() {
    final phase = awaitingPhase;
    if (phase == null) return null;
    final now = _now();
    final timeout = _stageTimeouts[phase] ?? const Duration(seconds: 12);
    return SttReadinessTimeoutMetadata(
      awaitingPhase: phase,
      stageElapsed: now - _stageStartedAt,
      totalElapsed: now - _sessionStartedAt,
      timeout: timeout,
    );
  }

  Duration _now() {
    final elapsed = _elapsedReader();
    if (elapsed > _lastElapsed) _lastElapsed = elapsed;
    return _lastElapsed;
  }

  static SttMonotonicElapsedReader _stopwatchReader() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

enum SttHostDiagnosticKind {
  lifecycle,
  timeout,
  failover,
  recovery,
  stopped,
  runtimeQuarantined,
  runtimeProbeUnavailable,
}

/// An allowlisted diagnostic payload. Its API intentionally has no fields for
/// URLs, tokens, transcript text, microphone identifiers, or command lines.
class SttHostDiagnosticData {
  SttHostDiagnosticData({
    required this.kind,
    required this.host,
    required this.phase,
    required this.elapsed,
    String? webView2RuntimeVersion,
    this.timeout,
  }) : exactRuntimeVersion =
            sanitizeWebView2RuntimeVersion(webView2RuntimeVersion);

  factory SttHostDiagnosticData.fromTimeout({
    required WindowsSttBrowserHost host,
    required SttReadinessTimeoutMetadata metadata,
    String? webView2RuntimeVersion,
  }) {
    return SttHostDiagnosticData(
      kind: SttHostDiagnosticKind.timeout,
      host: host,
      phase: metadata.awaitingPhase,
      elapsed: metadata.totalElapsed,
      timeout: metadata.timeout,
      webView2RuntimeVersion: webView2RuntimeVersion,
    );
  }

  final SttHostDiagnosticKind kind;
  final WindowsSttBrowserHost host;
  final SttHostReadinessPhase phase;
  final Duration elapsed;
  final String? exactRuntimeVersion;
  final Duration? timeout;

  Map<String, Object> toMap() {
    return <String, Object>{
      'event': kind.name,
      'host': host.name,
      'phase': phase.name,
      'elapsedMs': elapsed.inMilliseconds,
      if (exactRuntimeVersion != null) 'runtimeVersion': exactRuntimeVersion!,
      if (timeout != null) 'timeoutMs': timeout!.inMilliseconds,
    };
  }
}
