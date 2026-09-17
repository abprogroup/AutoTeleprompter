part of 'teleprompter_provider.dart';

const int externalEdgeNetworkFailureLimit = 3;

bool usesExternalEdgeSttHost(String? engine) =>
    AppSettings.normalizeSttEngine(engine) ==
    AppSettings.sttEngineBrowserExternalEdge;

String? embeddedSttWebViewUrlForHost({
  required bool usesExternalEdge,
  required String? adapterUrl,
}) => usesExternalEdge ? null : adapterUrl;

String externalEdgeSttLaunchFailureMessage([String? reason]) {
  final safeReason = reason?.trim();
  final prefix =
      safeReason == null || safeReason.isEmpty
          ? 'Microsoft Edge could not host speech recognition.'
          : safeReason;
  return '$prefix Choose Smart compatibility or Offline Whisper under '
      'Speech Input, or install Microsoft Edge and try again.';
}

String? externalEdgeRuntimeFailureReason({
  required String? error,
  required int consecutiveNetworkFailures,
}) {
  if (error == 'browser-disconnected') {
    return 'Microsoft Edge disconnected from speech recognition.';
  }
  if (consecutiveNetworkFailures >= externalEdgeNetworkFailureLimit) {
    return 'Microsoft Edge speech recognition repeatedly lost its network '
        'connection.';
  }
  return null;
}

extension TeleprompterExternalEdgeHost on TeleprompterNotifier {
  Future<void> _stopExternalEdgeHostServices() {
    final pending = _externalEdgeHostStopInFlight;
    if (pending != null) return pending;

    late final Future<void> stopFuture;
    stopFuture = Future.wait<void>([
      _externalEdgeLauncher.stop(),
      _browserSttService.stop(),
    ]).then<void>((_) {}).whenComplete(() {
      if (identical(_externalEdgeHostStopInFlight, stopFuture)) {
        _externalEdgeHostStopInFlight = null;
      }
    });
    _externalEdgeHostStopInFlight = stopFuture;
    return stopFuture;
  }

  bool _ensureExternalEdgeHostCanStart() {
    if (!_useExternalEdgeSttHost || !_externalEdgeLauncher.isRunning) {
      return true;
    }

    const reason =
        'The previous Microsoft Edge speech session could not be closed.';
    _addDebugLog('[Microsoft Edge fallback] $reason');
    LightweightDiagnostics.instance.record(
      'stt',
      'external Edge STT unavailable',
      data: const {'reasonCode': 'previous-edge-process-running'},
    );
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'previous-edge-process-running',
        quarantineRuntime: false,
      ),
    );
    return false;
  }

  Future<bool> _activateConfiguredBrowserSttHost({
    required int sessionToken,
  }) async {
    final adapterUrl = _sttService.sttWebViewUrl;
    final embeddedUrl = embeddedSttWebViewUrlForHost(
      usesExternalEdge: _useExternalEdgeSttHost,
      adapterUrl: adapterUrl,
    );

    if (!_useExternalEdgeSttHost) {
      if (embeddedUrl != null) {
        _safeSetState((s) => s.copyWith(sttWebViewUrl: embeddedUrl));
      }
      return true;
    }

    _safeSetState((s) => s.copyWith(sttWebViewUrl: null));
    if (_sttService != _browserSttService || adapterUrl == null) {
      return _failExternalEdgeHostStart(
        sessionToken: sessionToken,
        reason: 'The local speech-recognition page could not be prepared.',
      );
    }

    final launchResult = await _externalEdgeLauncher.launch(adapterUrl);
    if (_disposed || _sessionStopped || sessionToken != _sessionToken) {
      return false;
    }
    if (!launchResult.success) {
      return _failExternalEdgeHostStart(
        sessionToken: sessionToken,
        reason: launchResult.message,
      );
    }

    _advanceBrowserHostReadiness(
      SttHostReadinessPhase.hostLaunched,
      sessionToken: sessionToken,
    );

    _addDebugLog('[Microsoft Edge fallback] External speech host started.');
    LightweightDiagnostics.instance.record(
      'stt',
      'external Edge STT host started',
    );
    return true;
  }

  Future<bool> _failExternalEdgeHostStart({
    required int sessionToken,
    String? reason,
  }) async {
    _addDebugLog('[Microsoft Edge fallback] host launch failed.');
    LightweightDiagnostics.instance.record(
      'stt',
      'external Edge STT launch failed',
      data: const {'reasonCode': 'edge-launch-failed'},
    );
    if (!_sttHostTransitionInFlight) {
      await _handleBrowserHostFailure(
        reasonCode: 'edge-launch-failed',
        quarantineRuntime: false,
      );
    }
    return false;
  }
}
