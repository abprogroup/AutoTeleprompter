import 'dart:convert';

class DiagnosticEvent {
  final DateTime time;
  final String type;
  final String message;
  final Map<String, Object?> data;

  DiagnosticEvent({
    required this.time,
    required this.type,
    required this.message,
    this.data = const {},
  });

  Map<String, Object?> toJson() => {
        'time': time.toIso8601String(),
        'type': type,
        'message': message,
        if (data.isNotEmpty) 'data': data,
      };
}

class LightweightDiagnostics {
  LightweightDiagnostics._();

  static final LightweightDiagnostics instance = LightweightDiagnostics._();

  static const Duration retentionWindow = Duration(minutes: 30);
  static const int maxBytes = 512 * 1024;

  final List<DiagnosticEvent> _events = [];
  Object? _lastError;
  StackTrace? _lastStackTrace;

  void record(
    String type,
    String message, {
    Map<String, Object?> data = const {},
  }) {
    _events.add(DiagnosticEvent(
      time: DateTime.now().toUtc(),
      type: type,
      message: _trim(message, 800),
      data: _trimData(data),
    ));
    _prune();
  }

  void recordError(Object error, StackTrace? stackTrace, {String? source}) {
    _lastError = error;
    _lastStackTrace = stackTrace;
    record(
      'error',
      error.toString(),
      data: {
        if (source != null) 'source': source,
        if (stackTrace != null)
          'stackTrace': _trim(stackTrace.toString(), 8000),
      },
    );
  }

  Map<String, Object?> snapshot({
    int? budgetBytes,
    int stackTraceLimit = 2000,
  }) {
    _prune();
    final budget = budgetBytes ?? maxBytes;
    final eventJson = _events
        .map((event) => _eventJson(event, stackTraceLimit))
        .toList(growable: true);
    var dropped = 0;
    while (eventJson.isNotEmpty && _snapshotSize(eventJson) > budget) {
      eventJson.removeAt(0);
      dropped++;
    }
    return {
      'retentionMinutes': retentionWindow.inMinutes,
      'maxBytes': budget,
      if (dropped > 0) 'droppedEventCount': dropped,
      'events': eventJson,
      if (_lastError != null)
        'lastError': {
          'message': _lastError.toString(),
          if (_lastStackTrace != null)
            'stackTrace': _trim(_lastStackTrace.toString(), stackTraceLimit),
        },
    };
  }

  void clear() {
    _events.clear();
    _lastError = null;
    _lastStackTrace = null;
  }

  void _prune() {
    final cutoff = DateTime.now().toUtc().subtract(retentionWindow);
    _events.removeWhere((event) => event.time.isBefore(cutoff));
    while (_events.isNotEmpty && _encodedSize() > maxBytes) {
      _events.removeAt(0);
    }
  }

  int _encodedSize() => utf8
      .encode(jsonEncode({
        'events': _events.map((e) => e.toJson()).toList(growable: false),
      }))
      .length;

  int _snapshotSize(List<Map<String, Object?>> events) =>
      utf8.encode(jsonEncode({'events': events})).length;

  static Map<String, Object?> _eventJson(
    DiagnosticEvent event,
    int stackTraceLimit,
  ) =>
      {
        'time': event.time.toIso8601String(),
        'type': event.type,
        'message': event.message,
        if (event.data.isNotEmpty)
          'data': event.data.map((key, value) {
            if (key == 'stackTrace' && value is String) {
              return MapEntry(key, _trim(value, stackTraceLimit));
            }
            return MapEntry(key, value);
          }),
      };

  static String _trim(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }

  static Map<String, Object?> _trimData(Map<String, Object?> data) {
    return data.map((key, value) {
      if (value is String) return MapEntry(key, _trim(value, 1000));
      return MapEntry(key, value);
    });
  }
}
