import 'dart:async';

import 'package:autoteleprompter/platform/stt/stt_webview2_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('runtime sanitizer accepts exact versions and known channels only', () {
    expect(sanitizeWebView2RuntimeVersion('153.0.4234.32'), '153.0.4234.32');
    expect(
      sanitizeWebView2RuntimeVersion('153.0.4234.32 canary'),
      '153.0.4234.32',
    );
    expect(sanitizeWebView2RuntimeVersion('153.0.4234'), isNull);
    expect(
      sanitizeWebView2RuntimeVersion('153.0.4234.32?token=secret'),
      isNull,
    );
  });

  test('safe probe catches plugin failures and discards raw errors', () async {
    final probe = SafeWebView2RuntimeProbe(
      versionReader:
          () => Future<String?>.error(
            StateError('https://localhost/?token=secret'),
          ),
    );

    final result = await probe.probe();
    expect(result.status, WebView2RuntimeProbeStatus.unreadable);
    expect(result.exactVersion, isNull);
  });

  test('safe probe distinguishes absent and available runtime', () async {
    final absent =
        await SafeWebView2RuntimeProbe(versionReader: () async => null).probe();
    final available =
        await SafeWebView2RuntimeProbe(
          versionReader: () async => '153.0.4234.32 beta',
        ).probe();

    expect(absent.status, WebView2RuntimeProbeStatus.notInstalled);
    expect(available.status, WebView2RuntimeProbeStatus.available);
    expect(available.exactVersion, '153.0.4234.32');
  });

  test('safe probe bounds a platform call that never completes', () async {
    final blockedVersionRead = Completer<String?>();
    final result = await SafeWebView2RuntimeProbe(
      versionReader: () => blockedVersionRead.future,
      timeout: const Duration(milliseconds: 5),
    ).probe().timeout(const Duration(milliseconds: 100));

    expect(result.status, WebView2RuntimeProbeStatus.unreadable);
    expect(result.exactVersion, isNull);
  });

  test('quarantine expires entries and stores no failure context', () async {
    final now = DateTime.utc(2026, 9, 17);
    final expired = now.subtract(const Duration(days: 91));
    SharedPreferences.setMockInitialValues({
      '${WebView2RuntimeQuarantine.preferenceKeyPrefix}152.0.4191.66':
          expired.millisecondsSinceEpoch,
    });
    final preferences = await SharedPreferences.getInstance();
    final quarantine = WebView2RuntimeQuarantine(preferences, now: () => now);

    expect(await quarantine.contains('152.0.4191.66'), isFalse);
    await quarantine.quarantine('153.0.4234.32');
    expect(await quarantine.contains('153.0.4234.32'), isTrue);
    expect(preferences.getKeys(), {
      '${WebView2RuntimeQuarantine.preferenceKeyPrefix}153.0.4234.32',
    });
  });

  test('quarantine remains bounded to newest exact runtime versions', () async {
    var now = DateTime.utc(2026, 9, 17);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quarantine = WebView2RuntimeQuarantine(
      preferences,
      now: () => now,
      maxEntries: 2,
    );

    await quarantine.quarantine('151.0.1.1');
    now = now.add(const Duration(minutes: 1));
    await quarantine.quarantine('152.0.1.1');
    now = now.add(const Duration(minutes: 1));
    await quarantine.quarantine('153.0.1.1');

    expect(await quarantine.activeVersions(), ['153.0.1.1', '152.0.1.1']);
    expect(await quarantine.contains('151.0.1.1'), isFalse);
    expect(preferences.getKeys().length, 2);
  });

  test('malformed versions cannot create preference keys', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final quarantine = WebView2RuntimeQuarantine(preferences);

    await quarantine.quarantine('153.0.4234.32/token=secret');
    expect(preferences.getKeys(), isEmpty);
  });
}
