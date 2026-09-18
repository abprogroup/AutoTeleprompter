import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'stt_host_policy.dart';
import 'stt_host_readiness.dart';
import 'stt_webview2_compatibility.dart';

/// Reason codes that may be persisted in the local STT host event journal.
///
/// Keep this list explicit. Arbitrary browser errors, exception messages,
/// URLs, tokens, transcripts, command lines, and device details must never be
/// written to this journal.
const Set<String> sttHostJournalReasonCodes = <String>{
  'browser-disconnected',
  'browser-health-degraded',
  'browser-server-start-failed',
  'chrome-launch-failed',
  'edge-launch-failed',
  'edge-process-exited',
  'embedded-host-failed',
  'microphone-permission-denied',
  'network-failure-limit',
  'previous-edge-process-running',
  'previous-browser-process-running',
  'readiness-timeout',
  'speech-api-unavailable',
  'webview-init-failed',
  'webview-load-failed',
};

String? sanitizeSttHostJournalReasonCode(String? value) {
  if (value == null || !sttHostJournalReasonCodes.contains(value)) {
    return null;
  }
  return value;
}

/// A privacy-bounded STT host event that is safe to persist locally.
///
/// The type intentionally exposes no free-form diagnostic field.
class SttHostJournalEntry {
  const SttHostJournalEntry._({
    required this.timestampUtc,
    required this.event,
    required this.host,
    required this.phase,
    required this.elapsedMs,
    this.reasonCode,
    this.exactRuntimeVersion,
    this.timeoutMs,
  });

  final DateTime timestampUtc;
  final SttHostDiagnosticKind event;
  final WindowsSttBrowserHost host;
  final SttHostReadinessPhase phase;
  final String? reasonCode;
  final String? exactRuntimeVersion;
  final int elapsedMs;
  final int? timeoutMs;

  Map<String, Object> _toJson() => <String, Object>{
    'timestampUtc': timestampUtc.toUtc().toIso8601String(),
    'event': event.name,
    'host': host.name,
    'phase': phase.name,
    if (reasonCode != null) 'reasonCode': reasonCode!,
    if (exactRuntimeVersion != null) 'runtimeVersion': exactRuntimeVersion!,
    'elapsedMs': elapsedMs,
    if (timeoutMs != null) 'timeoutMs': timeoutMs!,
  };
}

/// Persists a small, allowlisted journal of STT host lifecycle events.
///
/// Methods return best-effort results and remain awaitable so callers can add
/// a short timeout without allowing diagnostics to block speech startup.
class SttHostEventJournal {
  SttHostEventJournal(
    this._preferences, {
    DateTime Function()? now,
    this.retention = defaultRetention,
    this.maxEvents = defaultMaxEvents,
    this.maxBytes = defaultMaxBytes,
  }) : _now = now ?? DateTime.now,
       assert(retention > Duration.zero),
       assert(maxEvents > 0),
       assert(maxBytes > 0);

  static const int schemaVersion = 1;
  static const String preferenceKey =
      'autoteleprompter.stt.host_event_journal.v1';
  static const Duration defaultRetention = Duration(days: 7);
  static const int defaultMaxEvents = 32;
  static const int defaultMaxBytes = 24 * 1024;
  static const int _maximumDurationMs = 7 * 24 * 60 * 60 * 1000;

  final SharedPreferences _preferences;
  final DateTime Function() _now;
  final Duration retention;
  final int maxEvents;
  final int maxBytes;

  Future<void> _operationTail = Future<void>.value();

  static Future<SttHostEventJournal> create() async {
    final preferences = await SharedPreferences.getInstance();
    return SttHostEventJournal(preferences);
  }

  Future<bool> record({
    required SttHostDiagnosticKind event,
    required WindowsSttBrowserHost host,
    required SttHostReadinessPhase phase,
    String? reasonCode,
    String? webView2RuntimeVersion,
    Duration elapsed = Duration.zero,
    Duration? timeout,
  }) {
    return _runExclusive(() async {
      try {
        final now = _now().toUtc();
        final events = _decodeAndBound(
          _preferences.getString(preferenceKey),
          now,
        )..add(
          SttHostJournalEntry._(
            timestampUtc: now,
            event: event,
            host: host,
            phase: phase,
            reasonCode: sanitizeSttHostJournalReasonCode(reasonCode),
            exactRuntimeVersion: sanitizeWebView2RuntimeVersion(
              webView2RuntimeVersion,
            ),
            elapsedMs: _boundedMilliseconds(elapsed),
            timeoutMs: timeout == null ? null : _boundedMilliseconds(timeout),
          ),
        );
        final bounded = _bound(events, now);
        return _preferences.setString(preferenceKey, _encode(bounded));
      } catch (_) {
        return false;
      }
    });
  }

  /// Returns retained events from oldest to newest.
  Future<List<SttHostJournalEntry>> read() {
    return _runExclusive(() async {
      try {
        final raw = _preferences.getString(preferenceKey);
        if (raw == null) return const <SttHostJournalEntry>[];
        if (!_rawWithinByteCap(raw)) {
          await _preferences.remove(preferenceKey);
          return const <SttHostJournalEntry>[];
        }

        final now = _now().toUtc();
        final events = _decodeAndBound(raw, now);
        if (events.isEmpty) {
          await _preferences.remove(preferenceKey);
          return const <SttHostJournalEntry>[];
        }

        final canonical = _encode(events);
        if (canonical != raw) {
          await _preferences.setString(preferenceKey, canonical);
        }
        return List<SttHostJournalEntry>.unmodifiable(events);
      } catch (_) {
        return const <SttHostJournalEntry>[];
      }
    });
  }

  Future<bool> clear() {
    return _runExclusive(() async {
      try {
        return _preferences.remove(preferenceKey);
      } catch (_) {
        return false;
      }
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  List<SttHostJournalEntry> _decodeAndBound(String? raw, DateTime now) {
    if (raw == null || !_rawWithinByteCap(raw)) {
      return <SttHostJournalEntry>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schema'] != schemaVersion) {
        return <SttHostJournalEntry>[];
      }
      final rawEvents = decoded['events'];
      if (rawEvents is! List) return <SttHostJournalEntry>[];

      final events = <SttHostJournalEntry>[];
      for (final rawEvent in rawEvents) {
        final event = _entryFromJson(rawEvent);
        if (event != null) events.add(event);
      }
      return _bound(events, now);
    } catch (_) {
      return <SttHostJournalEntry>[];
    }
  }

  List<SttHostJournalEntry> _bound(
    List<SttHostJournalEntry> source,
    DateTime now,
  ) {
    final cutoff = now.subtract(retention);
    final events = source
        .where(
          (event) =>
              !event.timestampUtc.isAfter(now) &&
              !event.timestampUtc.isBefore(cutoff),
        )
        .toList(growable: true)
      ..sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc));

    while (events.length > maxEvents) {
      events.removeAt(0);
    }
    while (events.isNotEmpty && _encodedByteLength(events) > maxBytes) {
      events.removeAt(0);
    }
    return events;
  }

  SttHostJournalEntry? _entryFromJson(Object? value) {
    if (value is! Map) return null;
    final timestampValue = value['timestampUtc'];
    final elapsedValue = value['elapsedMs'];
    if (timestampValue is! String || elapsedValue is! int) return null;

    final timestamp = DateTime.tryParse(timestampValue)?.toUtc();
    final event = _eventFromName(value['event']);
    final host = _hostFromName(value['host']);
    final phase = _phaseFromName(value['phase']);
    if (timestamp == null || event == null || host == null || phase == null) {
      return null;
    }

    final timeoutValue = value['timeoutMs'];
    return SttHostJournalEntry._(
      timestampUtc: timestamp,
      event: event,
      host: host,
      phase: phase,
      reasonCode: sanitizeSttHostJournalReasonCode(
        value['reasonCode'] is String ? value['reasonCode'] as String : null,
      ),
      exactRuntimeVersion: sanitizeWebView2RuntimeVersion(
        value['runtimeVersion'] is String
            ? value['runtimeVersion'] as String
            : null,
      ),
      elapsedMs: _boundedMillisecondsValue(elapsedValue),
      timeoutMs:
          timeoutValue is int ? _boundedMillisecondsValue(timeoutValue) : null,
    );
  }

  bool _rawWithinByteCap(String raw) {
    if (raw.length > maxBytes) return false;
    return utf8.encode(raw).length <= maxBytes;
  }

  String _encode(List<SttHostJournalEntry> events) =>
      jsonEncode(<String, Object>{
        'schema': schemaVersion,
        'events': events.map((event) => event._toJson()).toList(),
      });

  int _encodedByteLength(List<SttHostJournalEntry> events) =>
      utf8.encode(_encode(events)).length;

  static int _boundedMilliseconds(Duration duration) =>
      _boundedMillisecondsValue(duration.inMilliseconds);

  static int _boundedMillisecondsValue(int value) =>
      value.clamp(0, _maximumDurationMs).toInt();
}

SttHostDiagnosticKind? _eventFromName(Object? value) => switch (value) {
  'lifecycle' => SttHostDiagnosticKind.lifecycle,
  'timeout' => SttHostDiagnosticKind.timeout,
  'failover' => SttHostDiagnosticKind.failover,
  'recovery' => SttHostDiagnosticKind.recovery,
  'stopped' => SttHostDiagnosticKind.stopped,
  'runtimeQuarantined' => SttHostDiagnosticKind.runtimeQuarantined,
  'runtimeProbeUnavailable' => SttHostDiagnosticKind.runtimeProbeUnavailable,
  _ => null,
};

WindowsSttBrowserHost? _hostFromName(Object? value) => switch (value) {
  'embeddedWebView2' => WindowsSttBrowserHost.embeddedWebView2,
  'externalEdge' => WindowsSttBrowserHost.externalEdge,
  'externalChrome' => WindowsSttBrowserHost.externalChrome,
  _ => null,
};

SttHostReadinessPhase? _phaseFromName(Object? value) => switch (value) {
  'serverBound' => SttHostReadinessPhase.serverBound,
  'hostLaunched' => SttHostReadinessPhase.hostLaunched,
  'socketConnected' => SttHostReadinessPhase.socketConnected,
  'microphoneReady' => SttHostReadinessPhase.microphoneReady,
  'recognizerListening' => SttHostReadinessPhase.recognizerListening,
  _ => null,
};
