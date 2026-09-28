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

  test('every persisted setting resolves to Smart embedded mode', () {
    const persistedValues = <String?>[
      null,
      'windows_auto',
      'windows_offline',
      'browser_online',
      'browser_external_edge',
      'browser_external_chrome',
      'browser_smart_compatibility',
      'whisper_tiny',
      'whisper_base',
      'whisper_small',
      'whisper_medium',
      'google',
      'legacy_value',
    ];

    for (final value in persistedValues) {
      expect(
        WindowsSttHostMode.fromSetting(value),
        WindowsSttHostMode.smart,
        reason: 'Persisted setting "$value" must stay on the in-app host.',
      );
    }
  });

  test('Smart always starts the embedded WebView2 host', () async {
    for (final runtime in <String?>[
      null,
      '153.0.4234.32',
      '154.0.4300.1',
      '155.0.4400.7 canary',
    ]) {
      final policy = await WindowsSttHostPolicy.resolve(
        mode: WindowsSttHostMode.smart,
        webView2RuntimeVersion: runtime,
        quarantine: quarantine,
      );

      expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
      expect(policy.smartFailoverUsed, isFalse);
    }
  });

  test('a quarantined runtime remains on the embedded host', () async {
    await quarantine.quarantine('154.0.4300.1');

    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: quarantine,
    );

    expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
  });

  test('Smart retries embedded twice, then stops clearly', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: quarantine,
      embeddedRecoveryBudget: 2,
    );

    final first = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );
    final second = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );
    final exhausted = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );

    expect(first.action, WindowsSttHostAction.retry);
    expect(first.host, WindowsSttBrowserHost.embeddedWebView2);
    expect(first.reason, WindowsSttHostDecisionReason.embeddedRecovery);
    expect(first.embeddedRecoveriesUsed, 1);
    expect(second.action, WindowsSttHostAction.retry);
    expect(second.host, WindowsSttBrowserHost.embeddedWebView2);
    expect(second.embeddedRecoveriesUsed, 2);
    expect(exhausted.action, WindowsSttHostAction.stop);
    expect(exhausted.host, WindowsSttBrowserHost.embeddedWebView2);
    expect(
      exhausted.reason,
      WindowsSttHostDecisionReason.embeddedRecoveryExhausted,
    );
    expect(policy.smartFailoverUsed, isFalse);
  });

  test('Smart never switches to an external host after failure', () async {
    final policy = await WindowsSttHostPolicy.resolve(
      mode: WindowsSttHostMode.smart,
      webView2RuntimeVersion: '154.0.4300.1',
      quarantine: quarantine,
      embeddedRecoveryBudget: 0,
    );

    final embeddedFailure = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.embeddedWebView2,
    );
    final staleEdgeFailure = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.externalEdge,
    );
    final staleChromeFailure = await policy.handleFailure(
      failedHost: WindowsSttBrowserHost.externalChrome,
    );

    expect(embeddedFailure.action, WindowsSttHostAction.stop);
    expect(embeddedFailure.host, WindowsSttBrowserHost.embeddedWebView2);
    expect(
      embeddedFailure.reason,
      WindowsSttHostDecisionReason.embeddedRecoveryExhausted,
    );
    expect(staleEdgeFailure.action, WindowsSttHostAction.ignoreStaleFailure);
    expect(staleChromeFailure.action, WindowsSttHostAction.ignoreStaleFailure);
    expect(policy.currentHost, WindowsSttBrowserHost.embeddedWebView2);
    expect(policy.smartFailoverUsed, isFalse);
  });

  test('quarantine lookup timeout cannot block embedded startup', () async {
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
  });

  test('quarantine write cannot block an embedded retry decision', () async {
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

    expect(decision.action, WindowsSttHostAction.retry);
    expect(decision.host, WindowsSttBrowserHost.embeddedWebView2);
    await _waitUntil(() async => writeCalls == 1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });

  test(
    'observed runtime quarantine does not change the embedded route',
    () async {
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

      expect(decision.action, WindowsSttHostAction.retry);
      expect(decision.host, WindowsSttBrowserHost.embeddedWebView2);
      await _waitUntil(() async => persistedVersion != null);
      expect(persistedVersion, '155.0.4400.7');
    },
  );
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
