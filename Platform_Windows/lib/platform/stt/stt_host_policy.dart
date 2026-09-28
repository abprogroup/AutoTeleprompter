import 'dart:async';

import 'stt_webview2_compatibility.dart';

/// Runtime builds confirmed to break Web Speech in embedded WebView2 while
/// the same speech page continues to work in full Edge/Chrome.
const Set<String> knownIncompatibleWebView2SttVersions = {'153.0.4234.32'};

enum WindowsSttHostMode {
  smart,
  embeddedOnly,
  edgeOnly,
  chromeOnly;

  /// Maps persisted settings without making this policy depend on UI models.
  static WindowsSttHostMode fromSetting(String? value) {
    // V5 has one production host surface. Legacy values remain parseable in
    // AppSettings, but none may launch an external browser or offline engine.
    return WindowsSttHostMode.smart;
  }
}

enum WindowsSttBrowserHost { embeddedWebView2, externalEdge, externalChrome }

enum WindowsSttHostAction { retry, switchHost, stop, ignoreStaleFailure }

enum WindowsSttHostDecisionReason {
  embeddedRecovery,
  embeddedRecoveryExhausted,
  selectedHostFailed,
  staleHostFailure,
}

class WindowsSttHostDecision {
  const WindowsSttHostDecision({
    required this.action,
    required this.host,
    required this.reason,
    required this.embeddedRecoveriesUsed,
  });

  final WindowsSttHostAction action;
  final WindowsSttBrowserHost host;
  final WindowsSttHostDecisionReason reason;
  final int embeddedRecoveriesUsed;
}

/// Session-scoped policy for choosing and recovering the Windows browser host.
///
/// Smart mode is the V5 production path and stays inside the app's embedded
/// WebView2. It performs bounded in-place recovery, then stops with a clear
/// error. It never changes recognition engine or launches a top-level browser.
class WindowsSttHostPolicy {
  WindowsSttHostPolicy._({
    required this.mode,
    required WindowsSttBrowserHost initialHost,
    required this.exactWebView2RuntimeVersion,
    required WebView2RuntimeQuarantine? quarantine,
    required this.embeddedRecoveryBudget,
    required this.quarantineOperationTimeout,
  }) : _currentHost = initialHost,
       _quarantine = quarantine;

  final WindowsSttHostMode mode;
  final String? exactWebView2RuntimeVersion;

  final int embeddedRecoveryBudget;
  final Duration quarantineOperationTimeout;
  final WebView2RuntimeQuarantine? _quarantine;

  final WindowsSttBrowserHost _currentHost;
  int _embeddedRecoveriesUsed = 0;

  WindowsSttBrowserHost get currentHost => _currentHost;
  int get embeddedRecoveriesUsed => _embeddedRecoveriesUsed;
  bool get smartFailoverUsed => false;

  static Future<WindowsSttHostPolicy> resolve({
    required WindowsSttHostMode mode,
    required String? webView2RuntimeVersion,
    WebView2RuntimeQuarantine? quarantine,
    int embeddedRecoveryBudget = 2,
    Duration quarantineOperationTimeout = const Duration(seconds: 2),
  }) async {
    assert(embeddedRecoveryBudget >= 0);
    assert(quarantineOperationTimeout > Duration.zero);
    final version = sanitizeWebView2RuntimeVersion(webView2RuntimeVersion);
    final initialHost = switch (mode) {
      WindowsSttHostMode.edgeOnly => WindowsSttBrowserHost.externalEdge,
      WindowsSttHostMode.chromeOnly => WindowsSttBrowserHost.externalChrome,
      _ => WindowsSttBrowserHost.embeddedWebView2,
    };

    return WindowsSttHostPolicy._(
      mode: mode,
      initialHost: initialHost,
      exactWebView2RuntimeVersion: version,
      quarantine: quarantine,
      embeddedRecoveryBudget: embeddedRecoveryBudget,
      quarantineOperationTimeout: quarantineOperationTimeout,
    );
  }

  /// Applies a host failure and returns the only permitted next action.
  ///
  /// Set [quarantineWebViewRuntime] only for a demonstrated embedded-runtime
  /// compatibility/readiness failure. Permission and device errors should not
  /// quarantine the runtime. When the browser widget observed a newer exact
  /// runtime than the startup probe, pass it through
  /// [observedWebView2RuntimeVersion]; arbitrary values are discarded.
  Future<WindowsSttHostDecision> handleFailure({
    required WindowsSttBrowserHost failedHost,
    bool quarantineWebViewRuntime = false,
    String? observedWebView2RuntimeVersion,
  }) async {
    if (failedHost != _currentHost) {
      return _decision(
        WindowsSttHostAction.ignoreStaleFailure,
        WindowsSttHostDecisionReason.staleHostFailure,
      );
    }

    final observedVersion = sanitizeWebView2RuntimeVersion(
      observedWebView2RuntimeVersion,
    );
    final versionToQuarantine = observedVersion ?? exactWebView2RuntimeVersion;
    if (failedHost == WindowsSttBrowserHost.embeddedWebView2 &&
        quarantineWebViewRuntime &&
        versionToQuarantine != null) {
      _persistQuarantineBestEffort(versionToQuarantine);
    }

    if ((mode == WindowsSttHostMode.smart ||
            mode == WindowsSttHostMode.embeddedOnly) &&
        failedHost == WindowsSttBrowserHost.embeddedWebView2) {
      if (_embeddedRecoveriesUsed < embeddedRecoveryBudget) {
        _embeddedRecoveriesUsed += 1;
        return _decision(
          WindowsSttHostAction.retry,
          WindowsSttHostDecisionReason.embeddedRecovery,
        );
      }
      return _decision(
        WindowsSttHostAction.stop,
        WindowsSttHostDecisionReason.embeddedRecoveryExhausted,
      );
    }

    return _decision(
      WindowsSttHostAction.stop,
      WindowsSttHostDecisionReason.selectedHostFailed,
    );
  }

  WindowsSttHostDecision _decision(
    WindowsSttHostAction action,
    WindowsSttHostDecisionReason reason,
  ) {
    return WindowsSttHostDecision(
      action: action,
      host: _currentHost,
      reason: reason,
      embeddedRecoveriesUsed: _embeddedRecoveriesUsed,
    );
  }

  void _persistQuarantineBestEffort(String version) {
    final quarantine = _quarantine;
    if (quarantine == null) return;
    // Schedule persistence after the synchronous host decision. A slow or
    // unavailable preference backend must never hold up in-app recovery.
    unawaited(
      Future<void>.microtask(() async {
        try {
          await quarantine
              .quarantine(version)
              .timeout(quarantineOperationTimeout);
        } catch (_) {
          // The hard-coded compatibility floor and the next runtime probe still
          // protect startup. Persistence is intentionally best-effort.
        }
      }),
    );
  }
}
