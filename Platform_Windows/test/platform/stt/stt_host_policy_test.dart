import 'dart:async';

import 'package:autoteleprompter/platform/stt/stt_host_policy.dart';
import 'package:autoteleprompter/platform/stt/stt_webview2_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late WebView2RuntimeQuarantine quarantine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    quarantine = WebView2RuntimeQuarantine(
      preferences,
      now: () => DateTime.utc(2026, 9, 17),
    );
  });

  test('persisted engine values map to stable host modes', () {
    expect(
      WindowsSttHostMode.fromSetting('browser_online'),
      WindowsSttHostMode.embeddedOnly,
    );
    expect(
      WindowsSttHostMode.fromSetting('browser_external_edge'),
      WindowsSttHostMode.edgeOnly,
    );
    expect(
      WindowsSttHostMode.fromSetting('browser_external_chrome'),
      WindowsSttHostMode.chromeOnly,
    );
    expect(
      WindowsSttHostMode.fromSetting('browser_smart_compatibility'),
      WindowsSttHostMode.smart,
    );
    expect(
      WindowsSttHostMode.fromSetting('legacy_value'),
      WindowsSttHostMode.smart,
    );
  });

  test('Smart starts embedded when exact runtime is not quarantined', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
    expect(policy.smartFailoverUsed, isFalse);
  });

  test('Smart skips the confirmed incompatible WebView2 runtime', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '153.0.4234.32',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);
    expect(policy.smartFailoverUsed, isTrue);
  });

  test('Smart starts Edge when exact runtime is quarantined', () async {
    await quarantine.quarantine('154.0.4300.1');

    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);
    expect(policy.smartFailoverUsed, isTrue);
  });

  test(
    'Smart failover is one-way through Edge and Chrome and ignores stale hosts',
    () async {
      final policy = await WindowsSttHostPolicy.resolve(
        mode: WindowsSttHostMode.smart,
        webView2RuntimeVersion: '154.0.4300.1',
        quarantine: quarantine,
      );

      final failover = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.embeddedWebView2,
        quarantineWebViewRuntime: true,
      );
      final stale = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.embeddedWebView2,
      );
      final edgeFailure = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.externalEdge,
      );
      final staleEdge = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.externalEdge,
      );
      final chromeFailure = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.externalChrome,
      );

      expect(failover.action, WindowsSttHostAction.switchHost);
      expect(failover.host, WindowsSttBrowserHost.externalEdge);
      expect(stale.action, WindowsSttHostAction.ignoreStaleFailure);
      expect(edgeFailure.action, WindowsSttHostAction.switchHost);
      expect(edgeFailure.host, WindowsSttBrowserHost.externalChrome);
      expect(
        edgeFailure.reason,
        WindowsSttHostDecisionReason.smartChromeFailover,
      );
      expect(staleEdge.action, WindowsSttHostAction.ignoreStaleFailure);
      expect(chromeFailure.action, WindowsSttHostAction.stop);
      expect(policy.smartEdgeAttempted, isTrue);
      expect(policy.smartChromeAttempted, isTrue);
      await _waitUntil(() => quarantine.contains('154.0.4300.1'));
      expect(await quarantine.contains('154.0.4300.1'), isTrue);
    },
  );

  test('Smart remains usable without a persistent quarantine store', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
    );

    expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
    final decision = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
      quarantineWebViewRuntime: true,
    );
    expect(decision.action, WindowsSttHostAction.switchHost);
    expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);
  });

  test(
    'known incompatible runtime still selects Edge without a store',
    () async {
      final policy = await WindowsSttHostPolicy.resolve(
        mode: WindowsSttHostMode.smart,
        webView2RuntimeVersion: '153.0.4234.32',
      );

      expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);

      final edgeFailure = await policy.handleFailure(
        failedHost: WindowsSttBrowserHost.externalEdge,
      );
      expect(edgeFailure.action, WindowsSttHostAction.switchHost);
      expect(edgeFailure.host, WindowsSttBrowserHost.externalChrome);
    },
  );

  test(
    'quarantine lookup timeout cannot block initial host selection',
    () async {
      final blockedLookup = Completer<bool>();
      final controlled = _ControlledQuarantine(
        preferences,
        onContains: (_) => blockedLookup.future,
      );

      final policy = await WindowsSttHostPolicy.resolve(
        mode: WindowsSttHostMode.smart,
        webView2RuntimeVersion: '154.0.4300.1',
        quarantine: controlled,
        quarantineOperationTimeout: const Duration(milliseconds: 5),
      ).timeout(const Duration(milliseconds: 100));

      expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
    },
  );

  test('quarantine write cannot block the Smart failover decision', () async {
    final blockedWrite = Completer<void>();
    var writeCalls = 0;
    final controlled = _ControlledQuarantine(
      preferences,
      onContains: (_) async => false,
      onQuarantine: (_) {
        writeCalls += 1;
        return blockedWrite.future;
      },
    );
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: controlled,
      quarantineOperationTimeout: const Duration(milliseconds: 5),
    );

    final decision = await policy
        .handleFailure(
          failedHost: WindowsSttBrowserHost.embeddedWebView2,
          quarantineWebViewRuntime: true,
        )
        .timeout(const Duration(milliseconds: 100));

    expect(decision.action, WindowsSttHostAction.switchHost);
    expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);
    await _waitUntil(() async => writeCalls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  test('observed exact runtime overrides a missing startup probe', () async {
    String? persistedVersion;
    final controlled = _ControlledQuarantine(
      preferences,
      onQuarantine: (version) async {
        persistedVersion = version;
      },
    );
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: null,
      quarantine: controlled,
      quarantineOperationTimeout: const Duration(milliseconds: 50),
    );

    final decision = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
      quarantineWebViewRuntime: true,
      observedWebView2RuntimeVersion: '155.0.4400.7 canary',
    );

    expect(decision.action, WindowsSttHostAction.switchHost);
    await _waitUntil(() async => persistedVersion != null);
    expect(persistedVersion, '155.0.4400.7');
  });

  test('embedded-only mode has exactly two recovery attempts', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.embeddedOnly,
      webView2RuntimeVersion: '153.0.4234.32',
      quarantine: quarantine,
    );

    final first = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );
    final second = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );
    final third = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );

    expect(first.action, WindowsSttHostAction.retry);
    expect(second.action, WindowsSttHostAction.retry);
    expect(second.embeddedRecoveriesUsed, 2);
    expect(third.action, WindowsSttHostAction.stop);
    expect(
      third.reason,
      WindowsSttHostDecisionReason.embeddedRecoveryExhausted,
    );
  });

  test('Edge-only mode never enters embedded recovery', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.edgeOnly,
      webView2RuntimeVersion: '153.0.4234.32',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.externalEdge);
    final decision = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.externalEdge,
    );
    expect(decision.action, WindowsSttHostAction.stop);
  });

  test('Chrome-only mode never enters the Smart or embedded chain', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.chromeOnly,
      webView2RuntimeVersion: '153.0.4234.32',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.externalChrome);
    expect(policy.smartFailoverUsed, isFalse);
    final decision = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.externalChrome,
    );
    expect(decision.action, WindowsSttHostAction.stop);
    expect(decision.reason, WindowsSttHostDecisionReason.selectedHostFailed);
  });
}

class _ControlledQuarantine extends WebView2RuntimeQuarantine {
  _ControlledQuarantine(
    super.preferences, {
    this.onContains,
    this.onQuarantine,
  });

  final Future<bool> Function(String? version)? onContains;
  final Future<void> Function(String? version)? onQuarantine;

  @override
  Future<bool> contains(String? rawVersion) =>
      onContains?.call(rawVersion) ?? super.contains(rawVersion);

  @override
  Future<void> quarantine(String? rawVersion) =>
      onQuarantine?.call(rawVersion) ?? super.quarantine(rawVersion);
}

Future<void> _waitUntil(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition was not met before the focused-test deadline.');
}
