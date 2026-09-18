import 'package:autoteleprompter/platform/stt/stt_host_policy.dart';
import 'package:autoteleprompter/platform/stt/stt_host_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readiness advances only through the complete ordered handshake', () {
    var elapsed = Duration.zero;
    final readiness = SttHostReadinessStateMachine(
      elapsedReader: () => elapsed,
    );

    expect(
      readiness.advance(SttHostReadinessPhase.socketConnected),
      SttReadinessAdvanceResult.skipped,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.serverBound),
      SttReadinessAdvanceResult.advanced,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.serverBound),
      SttReadinessAdvanceResult.duplicate,
    );
    elapsed = const Duration(milliseconds: 20);
    expect(
      readiness.advance(SttHostReadinessPhase.hostLaunched),
      SttReadinessAdvanceResult.advanced,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.serverBound),
      SttReadinessAdvanceResult.regressive,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.socketConnected),
      SttReadinessAdvanceResult.advanced,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.microphoneReady),
      SttReadinessAdvanceResult.advanced,
    );
    expect(
      readiness.advance(SttHostReadinessPhase.recognizerListening),
      SttReadinessAdvanceResult.advanced,
    );
    expect(readiness.isReady, isTrue);
    expect(readiness.timeoutMetadata(), isNull);
  });

  test('timeout metadata identifies stage and monotonic elapsed time', () {
    var elapsed = Duration.zero;
    final readiness = SttHostReadinessStateMachine(
      stageTimeouts: const {
        SttHostReadinessPhase.serverBound: Duration(seconds: 3),
        SttHostReadinessPhase.hostLaunched: Duration(seconds: 5),
      },
      elapsedReader: () => elapsed,
    );

    elapsed = const Duration(seconds: 4);
    final first = readiness.timeoutMetadata()!;
    expect(first.awaitingPhase, SttHostReadinessPhase.serverBound);
    expect(first.stageElapsed, const Duration(seconds: 4));
    expect(first.isTimedOut, isTrue);

    expect(
      readiness.advance(SttHostReadinessPhase.serverBound),
      SttReadinessAdvanceResult.advanced,
    );
    elapsed = const Duration(seconds: 7);
    final second = readiness.timeoutMetadata()!;
    expect(second.awaitingPhase, SttHostReadinessPhase.hostLaunched);
    expect(second.stageElapsed, const Duration(seconds: 3));
    expect(second.totalElapsed, const Duration(seconds: 7));
    expect(second.isTimedOut, isFalse);

    elapsed = const Duration(seconds: 1);
    final clockRollback = readiness.timeoutMetadata()!;
    expect(clockRollback.totalElapsed, const Duration(seconds: 7));
    expect(clockRollback.stageElapsed, const Duration(seconds: 3));
  });

  test('structured diagnostics expose only allowlisted bounded fields', () {
    const metadata = SttReadinessTimeoutMetadata(
      awaitingPhase: SttHostReadinessPhase.socketConnected,
      stageElapsed: Duration(seconds: 12),
      totalElapsed: Duration(seconds: 18),
      timeout: Duration(seconds: 10),
    );
    final data = SttHostDiagnosticData.fromTimeout(
      host: WindowsSttBrowserHost.embeddedWebView2,
      metadata: metadata,
      webView2RuntimeVersion: '153.0.4234.32 canary',
    ).toMap();

    expect(data, {
      'event': 'timeout',
      'host': 'embeddedWebView2',
      'phase': 'socketConnected',
      'elapsedMs': 18000,
      'runtimeVersion': '153.0.4234.32',
      'timeoutMs': 10000,
    });
    expect(
      data.keys,
      isNot(
          contains(anyOf('url', 'token', 'transcript', 'deviceId', 'command'))),
    );
  });

  test('structured diagnostics omit malformed runtime data', () {
    final data = SttHostDiagnosticData(
      kind: SttHostDiagnosticKind.lifecycle,
      host: WindowsSttBrowserHost.externalEdge,
      phase: SttHostReadinessPhase.hostLaunched,
      elapsed: const Duration(milliseconds: 4),
      webView2RuntimeVersion: 'https://localhost/?token=secret',
    );
    expect(data.toMap().containsKey('runtimeVersion'), isFalse);
  });
}
