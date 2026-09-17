part of 'teleprompter_provider.dart';

const int _browserNetworkFailureLimit = 3;

bool shouldStartOfflineWhisperFallback({
  required WindowsSttHostMode mode,
  required WindowsSttBrowserHost failedHost,
  required WindowsSttHostAction action,
}) =>
    mode == WindowsSttHostMode.smart &&
    failedHost == WindowsSttBrowserHost.externalEdge &&
    action == WindowsSttHostAction.stop;

extension TeleprompterBrowserHost on TeleprompterNotifier {
  Future<bool> _prepareWindowsSttHostPolicy({
    required String sttEngine,
    required int sessionToken,
  }) async {
    _sttHostReadinessTimer?.cancel();
    _sttHostReadiness = null;
    _windowsSttHostPolicy = null;
    _sttHostTransitionGuard.invalidate();
    _pendingSttHostFailure = null;
    _pendingSttHostReadinessPhases.clear();
    _observedWebView2RuntimeVersion = null;
    _useExternalEdgeSttHost = false;

    if (_useWhisper || sttEngine == AppSettings.sttEngineWindowsOffline) {
      return true;
    }

    final probe = await SafeWebView2RuntimeProbe().probe();
    if (_disposed || _sessionStopped || sessionToken != _sessionToken) {
      return false;
    }

    final mode = WindowsSttHostMode.fromSetting(sttEngine);
    WindowsSttHostPolicy policy;
    try {
      final quarantine = await WebView2RuntimeQuarantine.create().timeout(
        const Duration(seconds: 2),
      );
      policy = await WindowsSttHostPolicy.resolve(
        mode: WindowsSttHostMode.fromSetting(sttEngine),
        webView2RuntimeVersion: probe.exactVersion,
        quarantine: quarantine,
      );
    } catch (_) {
      policy = await WindowsSttHostPolicy.resolve(
        mode: mode,
        webView2RuntimeVersion: probe.exactVersion,
      );
      LightweightDiagnostics.instance.record(
        'stt',
        'speech host compatibility store unavailable',
      );
    }
    if (_disposed || _sessionStopped || sessionToken != _sessionToken) {
      return false;
    }
    _windowsSttHostPolicy = policy;
    _useExternalEdgeSttHost =
        policy.currentHost == WindowsSttBrowserHost.externalEdge;
    if (probe.status != WebView2RuntimeProbeStatus.available) {
      _recordSttHostDiagnostic(
        SttHostDiagnosticKind.runtimeProbeUnavailable,
        phase: SttHostReadinessPhase.serverBound,
      );
    }
    if (_useExternalEdgeSttHost && policy.mode == WindowsSttHostMode.smart) {
      _addDebugLog(
        '[Smart speech host] This WebView2 version is quarantined; using Edge.',
      );
    }
    return true;
  }

  void _startBrowserHostReadiness({required int sessionToken}) {
    _sttHostReadinessTimer?.cancel();
    _pendingSttHostReadinessPhases.clear();
    _sttHostReadiness = SttHostReadinessStateMachine();
    _advanceBrowserHostReadiness(
      SttHostReadinessPhase.serverBound,
      sessionToken: sessionToken,
    );
  }

  void _advanceBrowserHostReadiness(
    SttHostReadinessPhase phase, {
    int? sessionToken,
  }) {
    final token = sessionToken ?? _sessionToken;
    if (_disposed || _sessionStopped || token != _sessionToken) return;
    final readiness = _sttHostReadiness;
    if (readiness == null) return;
    final result = readiness.advance(phase);
    if (result == SttReadinessAdvanceResult.skipped) {
      _pendingSttHostReadinessPhases.add(phase);
      return;
    }
    if (result != SttReadinessAdvanceResult.advanced) return;

    var completedPhase = phase;
    while (true) {
      _recordSttHostDiagnostic(
        SttHostDiagnosticKind.lifecycle,
        phase: completedPhase,
      );
      if (readiness.isReady) {
        _sttHostReadinessTimer?.cancel();
        _sttHostReadinessTimer = null;
        _pendingSttHostReadinessPhases.clear();
        return;
      }
      final awaiting = readiness.awaitingPhase;
      if (awaiting == null ||
          !_pendingSttHostReadinessPhases.remove(awaiting)) {
        break;
      }
      if (readiness.advance(awaiting) != SttReadinessAdvanceResult.advanced) {
        break;
      }
      completedPhase = awaiting;
    }
    _scheduleBrowserHostReadinessTimeout(token);
  }

  void _scheduleBrowserHostReadinessTimeout(int sessionToken) {
    _sttHostReadinessTimer?.cancel();
    final metadata = _sttHostReadiness?.timeoutMetadata();
    if (metadata == null) return;
    _sttHostReadinessTimer = Timer(metadata.timeout, () {
      _checkBrowserHostReadinessTimeout(sessionToken);
    });
  }

  void _checkBrowserHostReadinessTimeout(int sessionToken) {
    if (_disposed ||
        _sessionStopped ||
        sessionToken != _sessionToken ||
        _useWhisper) {
      return;
    }
    final metadata = _sttHostReadiness?.timeoutMetadata();
    if (metadata == null) return;
    if (!metadata.isTimedOut) {
      final remaining = metadata.timeout - metadata.stageElapsed;
      _sttHostReadinessTimer = Timer(
        remaining <= Duration.zero
            ? const Duration(milliseconds: 1)
            : remaining,
        () => _checkBrowserHostReadinessTimeout(sessionToken),
      );
      return;
    }

    final policy = _windowsSttHostPolicy;
    if (policy != null) {
      final payload =
          SttHostDiagnosticData.fromTimeout(
            host: policy.currentHost,
            metadata: metadata,
            webView2RuntimeVersion: policy.exactWebView2RuntimeVersion,
          ).toMap();
      LightweightDiagnostics.instance.record(
        'sttHost',
        'speech host readiness timeout',
        data: payload,
      );
    }
    final quarantineRuntime =
        metadata.awaitingPhase != SttHostReadinessPhase.microphoneReady;
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'readiness-timeout',
        quarantineRuntime: quarantineRuntime,
      ),
    );
  }

  void reportEmbeddedSttHostLoaded({String? runtimeVersion}) {
    final policy = _windowsSttHostPolicy;
    if (_disposed ||
        _sessionStopped ||
        _useWhisper ||
        policy?.currentHost != WindowsSttBrowserHost.embeddedWebView2) {
      return;
    }
    _advanceBrowserHostReadiness(SttHostReadinessPhase.hostLaunched);
    final version = sanitizeWebView2RuntimeVersion(runtimeVersion);
    _observedWebView2RuntimeVersion = version;
    if (version != null && version != policy?.exactWebView2RuntimeVersion) {
      LightweightDiagnostics.instance.record(
        'sttHost',
        'embedded runtime version observed',
        data: {'runtimeVersion': version},
      );
    }
  }

  void reportEmbeddedSttHostFailure({
    required String reasonCode,
    String? runtimeVersion,
  }) {
    final policy = _windowsSttHostPolicy;
    if (_disposed ||
        _sessionStopped ||
        _useWhisper ||
        policy?.currentHost != WindowsSttBrowserHost.embeddedWebView2) {
      return;
    }
    final safeReason = switch (reasonCode) {
      'webview-init-failed' || 'webview-load-failed' => reasonCode,
      _ => 'embedded-host-failed',
    };
    final observedVersion = sanitizeWebView2RuntimeVersion(runtimeVersion);
    if (observedVersion != null) {
      _observedWebView2RuntimeVersion = observedVersion;
    }
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: safeReason,
        quarantineRuntime: true,
        observedRuntimeVersion: observedVersion,
      ),
    );
  }

  void _handleUnexpectedEdgeExit(int exitCode) {
    final policy = _windowsSttHostPolicy;
    if (_disposed ||
        _sessionStopped ||
        _useWhisper ||
        policy?.currentHost != WindowsSttBrowserHost.externalEdge) {
      return;
    }
    LightweightDiagnostics.instance.record(
      'sttHost',
      'external Edge speech host exited',
      data: {'exitCode': exitCode},
    );
    if (_sttHostTransitionInFlight) {
      _pendingSttHostFailure ??= _PendingSttHostFailure(
        reasonCode: 'edge-process-exited',
        quarantineRuntime: false,
        sessionToken: _sessionToken,
        policy: policy!,
      );
      return;
    }
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'edge-process-exited',
        quarantineRuntime: false,
      ),
    );
  }

  void _handleBrowserHostRuntimeHealth(SttRuntimeHealth health) {
    if (_useWhisper || _disposed || _sessionStopped) return;
    switch (health.type) {
      case 'socketConnected':
        _advanceBrowserHostReadiness(SttHostReadinessPhase.socketConnected);
        return;
      case 'microphoneReady':
        _advanceBrowserHostReadiness(SttHostReadinessPhase.microphoneReady);
        return;
      case 'recognizerListening':
        _advanceBrowserHostReadiness(SttHostReadinessPhase.recognizerListening);
        return;
      case 'speechApiUnavailable':
        unawaited(
          _handleBrowserHostFailure(
            reasonCode: 'speech-api-unavailable',
            quarantineRuntime: true,
          ),
        );
        return;
      case 'permissionDenied':
        unawaited(
          _handleBrowserHostFailure(
            reasonCode: 'microphone-permission-denied',
            quarantineRuntime: false,
          ),
        );
        return;
      case 'disconnected':
        unawaited(
          _handleBrowserHostFailure(
            reasonCode: 'browser-disconnected',
            quarantineRuntime: true,
          ),
        );
        return;
      case 'network':
        _recoverableSttErrorCount += health.failures <= 0 ? 1 : health.failures;
        _lastRecoverableSttErrorAt = DateTime.now();
        if (_recoverableSttErrorCount >= _browserNetworkFailureLimit) {
          unawaited(
            _handleBrowserHostFailure(
              reasonCode: 'network-failure-limit',
              quarantineRuntime: true,
            ),
          );
        }
        return;
      case 'heartbeat':
        _lastBrowserHeartbeatAt = DateTime.now();
        if (health.failures <= 0) {
          _recoverableSttErrorCount = 0;
          _lastRecoverableSttErrorAt = null;
        }
        return;
    }
  }

  Future<void> _handleBrowserHostFailure({
    required String reasonCode,
    required bool quarantineRuntime,
    String? observedRuntimeVersion,
  }) async {
    if (_disposed ||
        _sessionStopped ||
        _useWhisper ||
        _sttHostTransitionInFlight) {
      return;
    }
    final sessionToken = _sessionToken;
    final policy = _windowsSttHostPolicy;
    final transitionOwner = _sttHostTransitionGuard.begin();
    _sttHostReadinessTimer?.cancel();
    final failedHost =
        policy?.currentHost ?? WindowsSttBrowserHost.embeddedWebView2;
    try {
      if (policy == null) {
        await _stopWithBrowserHostError(
          reasonCode,
          sessionToken: sessionToken,
          policy: policy,
          transitionOwner: transitionOwner,
        );
        return;
      }
      final decision = await policy.handleFailure(
        failedHost: failedHost,
        quarantineWebViewRuntime: quarantineRuntime,
        observedWebView2RuntimeVersion:
            observedRuntimeVersion ??
            (failedHost == WindowsSttBrowserHost.embeddedWebView2
                ? _observedWebView2RuntimeVersion
                : null),
      );
      if (!_ownsSttHostTransition(
        transitionOwner,
        sessionToken: sessionToken,
        policy: policy,
      )) {
        return;
      }
      _recordSttHostDiagnostic(
        switch (decision.action) {
          WindowsSttHostAction.retry => SttHostDiagnosticKind.recovery,
          WindowsSttHostAction.switchHost => SttHostDiagnosticKind.failover,
          WindowsSttHostAction.stop => SttHostDiagnosticKind.stopped,
          WindowsSttHostAction.ignoreStaleFailure =>
            SttHostDiagnosticKind.lifecycle,
        },
        phase:
            _sttHostReadiness?.completedPhase ??
            SttHostReadinessPhase.serverBound,
        reasonCode: reasonCode,
        host: failedHost,
      );
      switch (decision.action) {
        case WindowsSttHostAction.switchHost:
          await _restartBrowserHost(
            host: WindowsSttBrowserHost.externalEdge,
            reasonCode: reasonCode,
            sessionToken: sessionToken,
            policy: policy,
            transitionOwner: transitionOwner,
          );
          return;
        case WindowsSttHostAction.retry:
          await _restartBrowserHost(
            host: WindowsSttBrowserHost.embeddedWebView2,
            reasonCode: reasonCode,
            sessionToken: sessionToken,
            policy: policy,
            transitionOwner: transitionOwner,
          );
          return;
        case WindowsSttHostAction.stop:
          if (shouldStartOfflineWhisperFallback(
            mode: policy.mode,
            failedHost: failedHost,
            action: decision.action,
          )) {
            await _startOfflineWhisperFallback(
              reasonCode,
              sessionToken: sessionToken,
              policy: policy,
              transitionOwner: transitionOwner,
            );
          } else {
            await _stopWithBrowserHostError(
              reasonCode,
              sessionToken: sessionToken,
              policy: policy,
              transitionOwner: transitionOwner,
            );
          }
          return;
        case WindowsSttHostAction.ignoreStaleFailure:
          return;
      }
    } finally {
      _finishSttHostTransition(
        transitionOwner,
        sessionToken: sessionToken,
        policy: policy,
      );
    }
  }

  Future<void> _restartBrowserHost({
    required WindowsSttBrowserHost host,
    required String reasonCode,
    required int sessionToken,
    required WindowsSttHostPolicy policy,
    required int transitionOwner,
  }) async {
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final locale = _activeLocale ?? _scriptLanguageLocale ?? 'he_IL';
    _useExternalEdgeSttHost = host == WindowsSttBrowserHost.externalEdge;
    _externalEdgeFailureInFlight = false;
    _recoverableSttErrorCount = 0;
    _lastRecoverableSttErrorAt = null;
    _safeSetState(
      (s) => s.copyWith(
        sttWebViewUrl: null,
        isListening: false,
        isStarting: true,
        hasError: false,
        statusMessage: '',
      ),
    );
    await _stopExternalEdgeHostServices();
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }

    _browserSttService.setAudioInputDevice(
      settings.sttInputDeviceId.trim().isEmpty
          ? null
          : settings.sttInputDeviceId.trim(),
      label:
          settings.sttInputDeviceLabel.trim().isEmpty
              ? 'System default microphone'
              : settings.sttInputDeviceLabel.trim(),
    );
    final result = await _browserSttService.start(localeId: locale);
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }
    if (!result.success) {
      _handoffSttHostTransition(transitionOwner);
      await _handleBrowserHostFailure(
        reasonCode: 'browser-server-start-failed',
        quarantineRuntime: false,
      );
      return;
    }

    _sttService = _browserSttService;
    _activeSttCanSwitchLocale = true;
    _activeSttEngineLabel =
        host == WindowsSttBrowserHost.externalEdge
            ? 'Microsoft Edge compatibility speech-to-text'
            : 'Browser online speech-to-text';
    _startBrowserHostReadiness(sessionToken: sessionToken);
    final activated = await _activateConfiguredBrowserSttHost(
      sessionToken: sessionToken,
    );
    if (!activated &&
        _ownsSttHostTransition(
          transitionOwner,
          sessionToken: sessionToken,
          policy: policy,
        )) {
      _handoffSttHostTransition(transitionOwner);
      await _handleBrowserHostFailure(
        reasonCode:
            host == WindowsSttBrowserHost.externalEdge
                ? 'edge-launch-failed'
                : 'embedded-host-failed',
        quarantineRuntime: host == WindowsSttBrowserHost.embeddedWebView2,
      );
    }
  }

  Future<void> _startOfflineWhisperFallback(
    String reasonCode, {
    required int sessionToken,
    required WindowsSttHostPolicy policy,
    required int transitionOwner,
  }) async {
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }
    final locale = _activeLocale ?? _scriptLanguageLocale ?? 'he_IL';
    _sttHostReadinessTimer?.cancel();
    _sttHostReadiness = null;
    _safeSetState(
      (s) => s.copyWith(
        sttWebViewUrl: null,
        isListening: false,
        isStarting: true,
        hasError: false,
        statusMessage: 'Starting offline speech recognition...',
      ),
    );
    await _stopExternalEdgeHostServices();
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }

    _useExternalEdgeSttHost = false;
    _useWhisper = true;
    _activeSttCanSwitchLocale = false;
    _activeSttEngineLabel = 'Offline Whisper Tiny';
    _addDebugLog(
      '[Smart speech host] Browser hosts unavailable; starting offline Whisper.',
    );
    LightweightDiagnostics.instance.record(
      'sttHost',
      'switched to offline speech fallback',
      data: {'reasonCode': reasonCode, 'model': 'tiny'},
    );
    await _whisperService.start(localeId: locale, model: WhisperModel.tiny);
  }

  Future<void> _stopWithBrowserHostError(
    String reasonCode, {
    required int sessionToken,
    required WindowsSttHostPolicy? policy,
    required int transitionOwner,
  }) async {
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }
    _sttHostReadinessTimer?.cancel();
    final host = policy?.currentHost;
    final message = _browserHostFailureMessage(reasonCode, host);
    _startingSession = false;
    await _stopExternalEdgeHostServices();
    if (!_ownsSttHostTransition(
      transitionOwner,
      sessionToken: sessionToken,
      policy: policy,
    )) {
      return;
    }
    _safeSetState(
      (s) => s.copyWith(
        sttWebViewUrl: null,
        statusMessage: message,
        hasError: true,
        isListening: false,
        isStarting: false,
      ),
    );
  }

  String _browserHostFailureMessage(
    String reasonCode,
    WindowsSttBrowserHost? host,
  ) {
    if (reasonCode == 'microphone-permission-denied') {
      return 'Microphone access is blocked. Open Windows Settings > Privacy & '
          'security > Microphone and allow desktop apps.';
    }
    final hostName =
        host == WindowsSttBrowserHost.externalEdge
            ? 'Microsoft Edge'
            : 'the in-app browser';
    return 'Speech recognition could not become ready in $hostName. '
        'Choose Smart compatibility or Offline Whisper in Speech Input, then '
        'start listening again.';
  }

  void _recordSttHostDiagnostic(
    SttHostDiagnosticKind kind, {
    required SttHostReadinessPhase phase,
    String? reasonCode,
    WindowsSttBrowserHost? host,
  }) {
    final policy = _windowsSttHostPolicy;
    if (policy == null) return;
    final elapsed =
        _sessionStartTime == null
            ? Duration.zero
            : DateTime.now().difference(_sessionStartTime!);
    final payload =
        SttHostDiagnosticData(
          kind: kind,
          host: host ?? policy.currentHost,
          phase: phase,
          elapsed: elapsed,
          webView2RuntimeVersion: policy.exactWebView2RuntimeVersion,
        ).toMap();
    LightweightDiagnostics.instance.record(
      'sttHost',
      'speech host lifecycle',
      data: {...payload, if (reasonCode != null) 'reasonCode': reasonCode},
    );
  }

  bool _ownsSttHostTransition(
    int transitionOwner, {
    required int sessionToken,
    required WindowsSttHostPolicy? policy,
  }) =>
      !_disposed &&
      !_sessionStopped &&
      sessionToken == _sessionToken &&
      identical(policy, _windowsSttHostPolicy) &&
      _sttHostTransitionGuard.owns(transitionOwner);

  void _handoffSttHostTransition(int transitionOwner) {
    if (!_sttHostTransitionGuard.release(transitionOwner)) return;
    _pendingSttHostFailure = null;
  }

  void _finishSttHostTransition(
    int transitionOwner, {
    required int sessionToken,
    required WindowsSttHostPolicy? policy,
  }) {
    if (!_sttHostTransitionGuard.release(transitionOwner)) return;
    final pending = _pendingSttHostFailure;
    _pendingSttHostFailure = null;
    if (pending == null ||
        _disposed ||
        _sessionStopped ||
        pending.sessionToken != sessionToken ||
        sessionToken != _sessionToken ||
        !identical(pending.policy, policy) ||
        !identical(policy, _windowsSttHostPolicy)) {
      return;
    }
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: pending.reasonCode,
        quarantineRuntime: pending.quarantineRuntime,
      ),
    );
  }
}

class _PendingSttHostFailure {
  const _PendingSttHostFailure({
    required this.reasonCode,
    required this.quarantineRuntime,
    required this.sessionToken,
    required this.policy,
  });

  final String reasonCode;
  final bool quarantineRuntime;
  final int sessionToken;
  final WindowsSttHostPolicy policy;
}
