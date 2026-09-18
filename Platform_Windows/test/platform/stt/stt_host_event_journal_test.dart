import 'dart:convert';

import 'package:autoteleprompter/platform/stt/stt_host_event_journal.dart';
import 'package:autoteleprompter/platform/stt/stt_host_policy.dart';
import 'package:autoteleprompter/platform/stt/stt_host_readiness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists only allowlisted structured fields', () async {
    final now = DateTime.utc(2026, 9, 17, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(preferences, now: () => now);

    expect(
      await journal.record(
        event: SttHostDiagnosticKind.failover,
        host: WindowsSttBrowserHost.externalChrome,
        phase: SttHostReadinessPhase.hostLaunched,
        reasonCode: 'chrome-launch-failed',
        webView2RuntimeVersion: '153.0.4234.32 beta',
        elapsed: const Duration(milliseconds: 1250),
        timeout: const Duration(seconds: 12),
      ),
      isTrue,
    );

    final raw = preferences.getString(SttHostEventJournal.preferenceKey)!;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final events = decoded['events'] as List<dynamic>;
    final event = events.single as Map<String, dynamic>;

    expect(decoded.keys, <String>{'schema', 'events'});
    expect(event.keys, <String>{
      'timestampUtc',
      'event',
      'host',
      'phase',
      'reasonCode',
      'runtimeVersion',
      'elapsedMs',
      'timeoutMs',
    });
    expect(event['timestampUtc'], '2026-09-17T12:00:00.000Z');
    expect(event['event'], 'failover');
    expect(event['host'], 'externalChrome');
    expect(event['phase'], 'hostLaunched');
    expect(event['reasonCode'], 'chrome-launch-failed');
    expect(event['runtimeVersion'], '153.0.4234.32');
    expect(event['elapsedMs'], 1250);
    expect(event['timeoutMs'], 12000);
  });

  test('drops free-form values and rewrites injected fields', () async {
    const secret = 'https://localhost:8082/?session=private-token';
    final now = DateTime.utc(2026, 9, 17, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{
      SttHostEventJournal.preferenceKey: jsonEncode(<String, Object>{
        'schema': 1,
        'events': <Object>[
          <String, Object>{
            'timestampUtc': now.toIso8601String(),
            'event': 'lifecycle',
            'host': 'externalEdge',
            'phase': 'socketConnected',
            'reasonCode': secret,
            'runtimeVersion': '153.0.4234.32?token=private',
            'elapsedMs': 50,
            'transcript': 'private spoken text',
            'commandLine': secret,
            'deviceId': 'private-device',
            'exception': secret,
          },
        ],
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(preferences, now: () => now);

    final events = await journal.read();
    final persisted = preferences.getString(SttHostEventJournal.preferenceKey)!;

    expect(events, hasLength(1));
    expect(events.single.reasonCode, isNull);
    expect(events.single.exactRuntimeVersion, isNull);
    expect(persisted, isNot(contains('private')));
    expect(persisted, isNot(contains('localhost')));
    expect(persisted, isNot(contains('transcript')));
    expect(persisted, isNot(contains('commandLine')));
    expect(persisted, isNot(contains('deviceId')));
    expect(persisted, isNot(contains('exception')));
  });

  test('rejects unknown event host and phase values', () async {
    final now = DateTime.utc(2026, 9, 17, 12);
    Map<String, Object> event(String key, String value) => <String, Object>{
      'timestampUtc': now.toIso8601String(),
      'event': key == 'event' ? value : 'lifecycle',
      'host': key == 'host' ? value : 'externalEdge',
      'phase': key == 'phase' ? value : 'socketConnected',
      'elapsedMs': 10,
    };
    SharedPreferences.setMockInitialValues(<String, Object>{
      SttHostEventJournal.preferenceKey: jsonEncode(<String, Object>{
        'schema': 1,
        'events': <Object>[
          event('event', 'token=private'),
          event('host', 'private-host'),
          event('phase', 'private-phase'),
        ],
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(preferences, now: () => now);

    expect(await journal.read(), isEmpty);
    expect(preferences.getString(SttHostEventJournal.preferenceKey), isNull);
  });

  test('retains seven days and at most the newest 32 events', () async {
    var now = DateTime.utc(2026, 9, 1, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(preferences, now: () => now);

    await journal.record(
      event: SttHostDiagnosticKind.lifecycle,
      host: WindowsSttBrowserHost.embeddedWebView2,
      phase: SttHostReadinessPhase.serverBound,
    );
    now = now.add(const Duration(days: 8));
    for (var index = 0; index < 40; index++) {
      await journal.record(
        event: SttHostDiagnosticKind.lifecycle,
        host: WindowsSttBrowserHost.externalEdge,
        phase: SttHostReadinessPhase.socketConnected,
        elapsed: Duration(milliseconds: index),
      );
      now = now.add(const Duration(minutes: 1));
    }

    final events = await journal.read();
    expect(events, hasLength(32));
    expect(events.first.elapsedMs, 8);
    expect(events.last.elapsedMs, 39);
    expect(events.first.timestampUtc, DateTime.utc(2026, 9, 9, 12, 8));
  });

  test('enforces encoded byte cap by discarding oldest events', () async {
    var now = DateTime.utc(2026, 9, 17, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(
      preferences,
      now: () => now,
      maxBytes: 550,
    );

    for (var index = 0; index < 10; index++) {
      await journal.record(
        event: SttHostDiagnosticKind.timeout,
        host: WindowsSttBrowserHost.externalEdge,
        phase: SttHostReadinessPhase.microphoneReady,
        reasonCode: 'readiness-timeout',
        webView2RuntimeVersion: '153.0.4234.32',
        elapsed: Duration(milliseconds: index),
        timeout: const Duration(seconds: 15),
      );
      now = now.add(const Duration(seconds: 1));
    }

    final raw = preferences.getString(SttHostEventJournal.preferenceKey)!;
    final events = await journal.read();
    expect(utf8.encode(raw).length, lessThanOrEqualTo(550));
    expect(events.length, lessThan(10));
    expect(events.last.elapsedMs, 9);
  });

  test('clear removes the journal', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final journal = SttHostEventJournal(preferences);
    await journal.record(
      event: SttHostDiagnosticKind.lifecycle,
      host: WindowsSttBrowserHost.externalEdge,
      phase: SttHostReadinessPhase.hostLaunched,
    );

    expect(await journal.clear(), isTrue);
    expect(preferences.getString(SttHostEventJournal.preferenceKey), isNull);
  });
}
