part of 'teleprompter_provider.dart';

const int _browserNetworkFailureLimit = 3;
const Duration _browserNetworkFailureQuietResetAfter = Duration(seconds: 30);

int _browserHostFailurePriority(String reasonCode) => switch (reasonCode) {
  'microphone-permission-denied' => 4,
  'speech-api-unavailable' || 'browser-disconnected' => 3,
  'readiness-timeout' || 'browser-health-degraded' => 2,
  _ => 1,
};

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
    if (_sttHostEventJournal == null) {
      try {
        _sttHostEventJournal = await SttHostEventJournal.create().timeout(
          const Duration(milliseconds: 750),
        );
      } catch (_) {
        LightweightDiagnostics.instance.record(
          'stt',
          'speech host event journal unavailable',
        );
      }
    }

    final runtimeBootstrap = WebView2RuntimeBootstrap.current;
    final effectiveRuntimeVersion = sanitizeWebView2RuntimeVersion(
      runtimeBootstrap?.effectiveRuntimeVersion,
    );
    final WebView2RuntimeProbeResult probe;
    if (runtimeBootstrap != null) {
      probe =
          effectiveRuntimeVersion == null
              ? const WebView2RuntimeProbeResult.unreadable()
              : WebView2RuntimeProbeResult.available(effectiveRuntimeVersion);
    } else {
      // Production initializes WebView2 before runApp. Retain a bounded probe
      // only for tests or unusual entry points that bypass main().
      probe = await SafeWebView2RuntimeProbe().probe();
    }
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
    // V5 has one production speech surface: the hidden embedded WebView2.
    // Legacy host values remain parseable, but provider routing must never
    // turn them into a visible Edge/Chrome window.
    if (probe.status != WebView2RuntimeProbeStatus.available) {
      _recordSttHostDiagnostic(
        SttHostDiagnosticKind.runtimeProbeUnavailable,
        phase: SttHostReadinessPhase.serverBound,
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
        if (_pendingSttHostFailure?.reasonCode == 'readiness-timeout') {
          _pendingSttHostFailure = null;
        }
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
      _recordSttHostDiagnostic(
        SttHostDiagnosticKind.timeout,
        phase: metadata.awaitingPhase,
        timeout: metadata.timeout,
      );
    }
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: 'readiness-timeout',
        // A readiness timeout can be caused by a slow machine, microphone
        // prompt, or service outage. Only explicit WebView initialization,
        // load, or API incompatibility failures persist a runtime quarantine.
        quarantineRuntime: false,
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
            quarantineRuntime: false,
          ),
        );
        return;
      case 'network':
        final now = DateTime.now();
        final previousError = _lastRecoverableSttErrorAt;
        _recoverableSttErrorCount =
            previousError == null ||
                    now.difference(previousError) >=
                        _browserNetworkFailureQuietResetAfter
                ? 1
                : _recoverableSttErrorCount + 1;
        _lastRecoverableSttErrorAt = now;
        if (_recoverableSttErrorCount >= _browserNetworkFailureLimit) {
          unawaited(
            _handleBrowserHostFailure(
              reasonCode: 'network-failure-limit',
              // A cloud/ISP failure is not proof that this exact WebView2
              // runtime is incompatible. Advance this session without
              // persisting a months-long runtime ban.
              quarantineRuntime: false,
            ),
          );
        }
        return;
      case 'productiveResult':
        _recoverableSttErrorCount = 0;
        _lastRecoverableSttErrorAt = null;
        return;
      case 'heartbeat':
        final now = DateTime.now();
        _lastBrowserHeartbeatAt = now;
        final lastError = _lastRecoverableSttErrorAt;
        if (health.failures <= 0 ||
            (lastError != null &&
                now.difference(lastError) >=
                    _browserNetworkFailureQuietResetAfter)) {
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
    if (_disposed || _sessionStopped || _useWhisper) {
      return;
    }
    final policy = _windowsSttHostPolicy;
    final failedHost =
        policy?.currentHost ?? WindowsSttBrowserHost.embeddedWebView2;
    if (_sttHostTransitionInFlight) {
      // Source-host shutdown events are expected during a transition. Queue
      // only events emitted after the destination adapter installed its new
      // readiness generation.
      if (policy != null && _sttHostReadiness != null) {
        final candidate = _PendingSttHostFailure(
          reasonCode: reasonCode,
          quarantineRuntime: quarantineRuntime,
          observedRuntimeVersion: observedRuntimeVersion,
          sessionToken: _sessionToken,
          policy: policy,
          failedHost: failedHost,
        );
        final pending = _pendingSttHostFailure;
        if (pending == null ||
            _browserHostFailurePriority(candidate.reasonCode) >
                _browserHostFailurePriority(pending.reasonCode)) {
          _pendingSttHostFailure = candidate;
        }
      }
      return;
    }
    final sessionToken = _sessionToken;
    final transitionOwner = _sttHostTransitionGuard.begin();
    _sttHostReadinessTimer?.cancel();
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
          await _stopWithBrowserHostError(
            'external-host-disabled',
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
          await _stopWithBrowserHostError(
            reasonCode,
            sessionToken: sessionToken,
            policy: policy,
            transitionOwner: transitionOwner,
          );
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
    if (host != WindowsSttBrowserHost.embeddedWebView2) {
      await _stopWithBrowserHostError(
        'external-host-disabled',
        sessionToken: sessionToken,
        policy: policy,
        transitionOwner: transitionOwner,
      );
      return;
    }
    final settings = ref.read(settingsProvider);
    final locale = _activeLocale ?? _scriptLanguageLocale ?? 'he_IL';
    _browserHostStartedAt = DateTime.now();
    _lastBrowserHeartbeatAt = null;
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
    _sttHostReadinessTimer?.cancel();
    _sttHostReadinessTimer = null;
    _sttHostReadiness = null;
    _pendingSttHostReadinessPhases.clear();
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
    _activeSttEngineLabel = 'Hidden in-app speech-to-text';
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
        reasonCode: 'embedded-host-failed',
        quarantineRuntime: true,
      );
    }
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
    if (reasonCode == 'edge-launch-failed') {
      return 'The external Edge speech host is disabled in this V5 build. '
          'Restart listening to use hidden in-app speech recognition.';
    }
    if (reasonCode == 'chrome-launch-failed') {
      return 'The external Chrome speech host is disabled in this V5 build. '
          'Restart listening to use hidden in-app speech recognition.';
    }
    if (reasonCode == 'external-host-disabled' ||
        host == WindowsSttBrowserHost.externalEdge ||
        host == WindowsSttBrowserHost.externalChrome) {
      return 'This V5 build supports speech recognition only inside the app. '
          'Restart listening to use the hidden in-app speech host.';
    }
    return 'Hidden in-app speech recognition could not become ready. Restart '
        'listening. If this repeats, reinstall the complete build so its '
        'compatible WebView2 runtime is available.';
  }

  void _recordSttHostDiagnostic(
    SttHostDiagnosticKind kind, {
    required SttHostReadinessPhase phase,
    String? reasonCode,
    WindowsSttBrowserHost? host,
    Duration? timeout,
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
          timeout: timeout,
        ).toMap();
    LightweightDiagnostics.instance.record(
      'sttHost',
      'speech host lifecycle',
      data: {...payload, if (reasonCode != null) 'reasonCode': reasonCode},
    );
    final journal = _sttHostEventJournal;
    if (journal != null) {
      unawaited(
        journal
            .record(
              event: kind,
              host: host ?? policy.currentHost,
              phase: phase,
              reasonCode: reasonCode,
              webView2RuntimeVersion: policy.exactWebView2RuntimeVersion,
              elapsed: elapsed,
              timeout: timeout,
            )
            .timeout(const Duration(milliseconds: 500))
            .then<void>((_) {}, onError: (_) {}),
      );
    }
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
        !identical(policy, _windowsSttHostPolicy) ||
        policy == null ||
        pending.failedHost != policy.currentHost) {
      return;
    }
    unawaited(
      _handleBrowserHostFailure(
        reasonCode: pending.reasonCode,
        quarantineRuntime: pending.quarantineRuntime,
        observedRuntimeVersion: pending.observedRuntimeVersion,
      ),
    );
  }
}

class _PendingSttHostFailure {
  const _PendingSttHostFailure({
    required this.reasonCode,
    required this.quarantineRuntime,
    required this.observedRuntimeVersion,
    required this.sessionToken,
    required this.policy,
    required this.failedHost,
  });

  final String reasonCode;
  final bool quarantineRuntime;
  final String? observedRuntimeVersion;
  final int sessionToken;
  final WindowsSttHostPolicy policy;
  final WindowsSttBrowserHost failedHost;
}
