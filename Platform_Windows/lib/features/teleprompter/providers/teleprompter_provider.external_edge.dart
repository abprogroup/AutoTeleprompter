part of 'teleprompter_provider.dart';

const int externalEdgeNetworkFailureLimit = 3;

bool usesExternalEdgeSttHost(String? engine) =>
    AppSettings.normalizeSttEngine(engine) ==
    AppSettings.sttEngineBrowserExternalEdge;

bool usesExternalChromeSttHost(String? engine) =>
    AppSettings.normalizeSttEngine(engine) ==
    AppSettings.sttEngineBrowserExternalChrome;

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
  void _initializeSpeechServices() {
    _browserSttService = SttServiceFactory.createWindowsBrowser();
    _desktopSttService = SttServiceFactory.createWindowsDesktop();
    _sttService = _browserSttService;
    _whisperService = WhisperSpeechService();
    _externalEdgeLauncher = WindowsSttExternalEdgeLauncher();
    _externalChromeLauncher = WindowsSttExternalChromeLauncher();
    _remoteControlService = ref.read(remoteControlProvider);
    _setupRemoteCallbacks();
    _setupSttCallbacks(_browserSttService);
    _setupSttCallbacks(_desktopSttService);
    _setupWhisperCallbacks();
  }

  Future<void> _stopExternalEdgeHostServices() {
    final pending = _externalEdgeHostStopInFlight;
    if (pending != null) return pending;

    late final Future<void> stopFuture;
    stopFuture = (() async {
      // Give the authenticated local page a chance to close its own browser
      // window before terminating the launcher-owned bootstrap process.
      await _browserSttService.stop();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await Future.wait<void>([
        _externalEdgeLauncher.stop(),
        _externalChromeLauncher.stop(),
      ]);
    })().whenComplete(() {
      if (identical(_externalEdgeHostStopInFlight, stopFuture)) {
        _externalEdgeHostStopInFlight = null;
      }
    });
    _externalEdgeHostStopInFlight = stopFuture;
    return stopFuture;
  }

  bool _ensureExternalEdgeHostCanStart() {
    final launcher = _selectedExternalBrowserLauncher;
    if (launcher == null || !launcher.isRunning) {
      return true;
    }

    final browserName = _selectedExternalBrowserName;
    final reason =
        'The previous $browserName speech session could not be closed.';
    _addDebugLog('[$browserName fallback] $reason');
    LightweightDiagnostics.instance.record(
      'stt',
      'external browser STT unavailable',
      data: {
        'host': _selectedExternalBrowserHostName,
        'reasonCode': 'previous-browser-process-running',
      },
    );
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'previous-browser-process-running',
        quarantineRuntime: false,
      ),
    );
    return false;
  }

  Future<bool> _activateConfiguredBrowserSttHost({
    required int sessionToken,
  }) async {
    final adapterUrl = _sttService.sttWebViewUrl;
    final usesExternalBrowser =
        _useExternalEdgeSttHost || _useExternalChromeSttHost;
    final embeddedUrl = embeddedSttWebViewUrlForHost(
      usesExternalEdge: usesExternalBrowser,
      adapterUrl: adapterUrl,
    );

    if (!usesExternalBrowser) {
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

    final launcher = _selectedExternalBrowserLauncher;
    if (launcher == null) {
      return _failExternalEdgeHostStart(
        sessionToken: sessionToken,
        reason: 'The selected external browser host is unavailable.',
      );
    }
    final launchResult = await launcher.launch(adapterUrl);
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

    final browserName = _selectedExternalBrowserName;
    _addDebugLog('[$browserName fallback] External speech host started.');
    LightweightDiagnostics.instance.record(
      'stt',
      'external browser STT host started',
      data: {'host': _selectedExternalBrowserHostName},
    );
    return true;
  }

  Future<bool> _failExternalEdgeHostStart({
    required int sessionToken,
    String? reason,
  }) async {
    final browserName = _selectedExternalBrowserName;
    final reasonCode =
        _useExternalChromeSttHost
            ? 'chrome-launch-failed'
            : 'edge-launch-failed';
    final safeReason = _safeExternalBrowserFailureReason(reason);
    _addDebugLog(
      '[$browserName fallback] host launch failed'
      '${safeReason == null ? "." : ": $safeReason"}',
    );
    LightweightDiagnostics.instance.record(
      'stt',
      'external browser STT launch failed',
      data: {
        'host': _selectedExternalBrowserHostName,
        'reasonCode': reasonCode,
      },
    );
    if (!_sttHostTransitionInFlight) {
      await _handleBrowserHostFailure(
        reasonCode: reasonCode,
        quarantineRuntime: false,
      );
    }
    return false;
  }

  String? _safeExternalBrowserFailureReason(String? reason) {
    final normalized = reason?.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized.length <= 180
        ? normalized
        : '${normalized.substring(0, 177)}...';
  }

  WindowsSttExternalBrowserLauncher? get _selectedExternalBrowserLauncher {
    if (_useExternalChromeSttHost) return _externalChromeLauncher;
    if (_useExternalEdgeSttHost) return _externalEdgeLauncher;
    return null;
  }

  String get _selectedExternalBrowserName =>
      _useExternalChromeSttHost ? 'Google Chrome' : 'Microsoft Edge';

  String get _selectedExternalBrowserHostName =>
      _useExternalChromeSttHost ? 'externalChrome' : 'externalEdge';
}
