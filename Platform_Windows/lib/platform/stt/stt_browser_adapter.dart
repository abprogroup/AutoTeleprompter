import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpServer;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

part 'stt_browser_adapter.page.dart';

/// Windows STT via Web Speech API running inside the embedded WebView2.
///
/// Serves a local HTML page that runs SpeechRecognition and sends results
/// back via WebSocket. The page is loaded directly by the WebviewController
/// so no external browser is involved.
///
/// Microphone access is handled by the current WebView2 profile. This adapter
/// only owns the local session server and rejects stale browser events.
class SttBrowserAdapter extends AbstractSttService {
  static const int _defaultPort = 8082;
  static const int _maxFallbackPort = 8092;
  static const Map<String, String> _htmlHeaders = {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };
  static const Map<String, String> _textHeaders = {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };

  HttpServer? _server;
  WebSocketChannel? _wsClient;
  bool _isActive = false;
  bool _everListened = false;
  String _currentLocale = 'en-US';
  String? _selectedAudioInputDeviceId;
  String _selectedAudioInputDeviceLabel = 'System default microphone';
  List<SttAudioInputDevice> _audioInputDevices = const [];
  int _sessionId = 0;
  int _port = _defaultPort;

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    _isActive = true;
    _everListened = false;
    _currentLocale = (localeId ?? 'en-US').replaceAll('_', '-');
    _sessionId++;
    final sessionId = _sessionId;

    onDiagnostic
        ?.call('[Browser STT] Starting local server on port $_defaultPort...');

    await _stopServer();

    final router = Router();

    router.get('/', (Request req) {
      return Response.ok(
        _buildHtml(_currentLocale, _selectedAudioInputDeviceId),
        headers: _htmlHeaders,
      );
    });

    router.get('/ws', (Request request) {
      final requestedSession =
          int.tryParse(request.url.queryParameters['session'] ?? '');
      if (!_isActive ||
          requestedSession == null ||
          requestedSession != sessionId ||
          requestedSession != _sessionId) {
        onDiagnostic?.call(
            '[Browser STT] rejected stale WebView session=$requestedSession active=$_sessionId');
        return Response.forbidden('stale session', headers: _textHeaders);
      }

      return webSocketHandler((WebSocketChannel channel) {
        final previousClient = _wsClient;
        _wsClient = channel;
        if (previousClient != null && previousClient != channel) {
          try {
            previousClient.sink.close();
          } catch (error) {
            _reportAdapterFailure(
              'closeStaleSocket',
              error,
              'failed to close stale WebView socket',
            );
          }
        }
        onDiagnostic?.call('[Browser STT] WebView connected');

        channel.stream.listen(
          (message) {
            if (!_isActive || _sessionId != sessionId || _wsClient != channel) {
              return;
            }
            try {
              final data =
                  jsonDecode(message as String) as Map<String, dynamic>;
              final type = data['type'] as String? ?? '';
              switch (type) {
                case 'devices':
                  final rawDevices = data['devices'];
                  if (rawDevices is List) {
                    final devices = rawDevices
                        .whereType<Map>()
                        .map((raw) {
                          final id = raw['id'] as String? ?? '';
                          final label = raw['label'] as String? ?? '';
                          return SttAudioInputDevice(
                            id: id,
                            label: label.isEmpty ? 'Microphone' : label,
                          );
                        })
                        .where((device) => device.id.isNotEmpty)
                        .toList();
                    _audioInputDevices = devices;
                    onAudioInputDevicesChanged?.call(devices);
                  }
                  break;
                case 'listening':
                  if (!_everListened) {
                    _everListened = true;
                    onStatusChange?.call(SpeechStatus.listening);
                    onDiagnostic?.call(
                        '[Browser STT] Web Speech API active - speak now');
                  }
                  break;
                case 'result':
                  final words = data['words'] as String? ?? '';
                  final isFinal = data['isFinal'] as bool? ?? false;
                  if (words.isNotEmpty) {
                    onResult?.call(SpeechResult(words, isFinal));
                  }
                  break;
                case 'level':
                  final level = (data['level'] as num?)?.toDouble() ?? 0.0;
                  onSoundLevelChange?.call(level);
                  break;
                case 'inputReady':
                  final label = data['label'] as String? ?? '';
                  if (label.isNotEmpty) {
                    _selectedAudioInputDeviceLabel = label;
                  }
                  onDiagnostic?.call(
                      '[Browser STT] Input ready: $_selectedAudioInputDeviceLabel');
                  break;
                case 'watchdogRestart':
                  final reason = data['reason'] as String? ?? 'stale';
                  final ageMs = (data['ageMs'] as num?)?.toInt() ?? 0;
                  onRuntimeHealth?.call(SttRuntimeHealth(
                    type: 'watchdogRestart',
                    listening: true,
                    locale: _currentLocale,
                    ageMs: ageMs,
                    failures: (data['failures'] as num?)?.toInt() ?? 0,
                  ));
                  onDiagnostic?.call(
                      '[Browser STT] Restarting recognizer after ${ageMs ~/ 1000}s without speech events ($reason)');
                  break;
                case 'heartbeat':
                  onRuntimeHealth?.call(SttRuntimeHealth(
                    type: 'heartbeat',
                    listening: data['listening'] as bool? ?? false,
                    locale: data['locale'] as String? ?? _currentLocale,
                    ageMs: (data['ageMs'] as num?)?.toInt() ?? 0,
                    failures: (data['failures'] as num?)?.toInt() ?? 0,
                  ));
                  break;
                case 'error':
                  final err = data['error'] as String? ?? 'unknown';
                  onRuntimeHealth?.call(SttRuntimeHealth(
                    type: 'error',
                    listening: _everListened,
                    locale: _currentLocale,
                    failures: err == 'network' ? 1 : 0,
                    error: err,
                  ));
                  if (err == 'input-device-missing') {
                    onDiagnostic?.call(
                        '[Browser STT] Selected microphone unavailable; using system default.');
                  } else if (err == 'input-device-failed') {
                    onDiagnostic?.call(
                        '[Browser STT] Could not open selected microphone; using system default.');
                  } else if (err == 'not-allowed') {
                    onError?.call('Microphone blocked in WebView2.\n'
                        'Grant mic access once: open http://localhost:$_port/ in Edge, '
                        'allow microphone, then restart the session.');
                  } else if (err != 'aborted' && err != 'no-speech') {
                    onDiagnostic?.call('[Browser STT] error: $err');
                  }
                  break;
              }
            } catch (error) {
              _reportAdapterFailure(
                'malformedMessage',
                error,
                'ignored malformed WebView message',
              );
            }
          },
          onDone: () {
            final wasCurrentClient = _wsClient == channel;
            if (wasCurrentClient) {
              _wsClient = null;
            }
            if (_isActive && wasCurrentClient) {
              onDiagnostic?.call('[Browser STT] WebView disconnected');
            }
          },
        );
      })(request);
    });

    try {
      _server = await _serveOnAvailablePort(router.call);
    } catch (e) {
      _isActive = false;
      return SpeechStartResult(
        success: false,
        message: 'Could not start speech-to-text server on ports '
            '$_defaultPort-$_maxFallbackPort: $e',
      );
    }

    onDiagnostic?.call(
        '[Browser STT] WebView ready at http://localhost:$_port/?session=$_sessionId');

    return SpeechStartResult(
      success: true,
      actualLocale: _currentLocale,
      requestedLocale: localeId,
    );
  }

  /// Hot-switch recognition locale without restarting the session.
  @override
  void setLocale(String locale) {
    final normalized = locale.replaceAll('_', '-');
    if (normalized == _currentLocale) return;
    _currentLocale = normalized;
    _everListened = false;
    onDiagnostic?.call('[Browser STT] Switching locale -> $normalized');
    try {
      _wsClient?.sink
          .add(jsonEncode({'type': 'setLocale', 'locale': normalized}));
    } catch (error) {
      _reportAdapterFailure(
        'sendLocale',
        error,
        'failed to send locale change',
      );
    }
  }

  @override
  void setAudioInputDevice(String? deviceId, {String? label}) {
    final normalized =
        deviceId == null || deviceId.trim().isEmpty ? null : deviceId.trim();
    _selectedAudioInputDeviceId = normalized;
    _selectedAudioInputDeviceLabel = (label == null || label.trim().isEmpty)
        ? 'System default microphone'
        : label.trim();
    onDiagnostic?.call(normalized == null
        ? '[Browser STT] Using system default microphone'
        : '[Browser STT] Requested microphone: $_selectedAudioInputDeviceLabel');
    try {
      _wsClient?.sink.add(jsonEncode({
        'type': 'setAudioInputDevice',
        'deviceId': normalized ?? '',
        'label': _selectedAudioInputDeviceLabel,
      }));
    } catch (error) {
      _reportAdapterFailure(
        'sendMicrophone',
        error,
        'failed to send microphone change',
      );
    }
  }

  @override
  Future<List<SttAudioInputDevice>> refreshAudioInputDevices() async {
    try {
      _wsClient?.sink.add(jsonEncode({'type': 'refreshAudioInputDevices'}));
    } catch (error) {
      _reportAdapterFailure(
        'refreshMicrophones',
        error,
        'failed to refresh microphones',
      );
    }
    return _audioInputDevices;
  }

  Future<void> _stopServer() async {
    final client = _wsClient;
    _wsClient = null;
    try {
      client?.sink.close();
    } catch (error) {
      _reportAdapterFailure(
        'closeSocket',
        error,
        'failed to close WebView socket',
      );
    }
    try {
      await _server?.close(force: true);
    } catch (error) {
      _reportAdapterFailure(
        'closeServer',
        error,
        'failed to close local server',
      );
    }
    _server = null;
  }

  void _reportAdapterFailure(String type, Object error, String message) {
    onDiagnostic?.call('[Browser STT] $message: ${error.runtimeType}');
    onRuntimeHealth?.call(SttRuntimeHealth(
      type: 'adapterFailure.$type',
      listening: _isActive,
      locale: _currentLocale,
      failures: 1,
      error: error.toString(),
    ));
  }

  Future<HttpServer> _serveOnAvailablePort(Handler handler) async {
    Object? lastError;
    for (var port = _defaultPort; port <= _maxFallbackPort; port++) {
      try {
        final server = await shelf_io.serve(handler, 'localhost', port);
        _port = port;
        if (port != _defaultPort) {
          onDiagnostic?.call(
              '[Browser STT] default port busy; using fallback port $port');
        }
        return server;
      } catch (e) {
        lastError = e;
        onDiagnostic?.call('[Browser STT] port $port unavailable: $e');
      }
    }
    throw lastError ?? StateError('No speech-to-text ports available');
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    await _stopServer();
    onStatusChange?.call(SpeechStatus.idle);
  }

  @override
  bool get isListening => _isActive;

  @override
  String get platformName => 'Browser Online';

  /// URL loaded by the embedded WebviewController (the STT page itself).
  @override
  String? get sttWebViewUrl =>
      _server != null ? 'http://localhost:$_port/?session=$_sessionId' : null;
}
