import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpServer;
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'abstract_stt_service.dart';
import 'stt_browser_lifecycle.dart';
import '../../features/teleprompter/services/speech_service.dart';

part 'stt_browser_adapter.page.dart';

/// Windows STT via Web Speech API running in an approved Chromium host.
///
/// Serves a local HTML page that runs SpeechRecognition and sends results
/// back via WebSocket. The normal host is the embedded WebView2; an explicit
/// compatibility mode may load the same authenticated loopback page in Edge.
///
/// Microphone access is handled by the selected browser host's dedicated
/// profile. This adapter only owns the local server and rejects stale events.
class SttBrowserAdapter extends AbstractSttService {
  static const int _defaultPort = 8082;
  static const int _maxFallbackPort = 8092;
  static const Map<String, String> _baseHtmlHeaders = {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'cross-origin-resource-policy': 'same-origin',
  };
  static const Map<String, String> _textHeaders = {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };
  static final Random _secureRandom = Random.secure();

  HttpServer? _server;
  WebSocketChannel? _wsClient;
  Completer<void>? _closeAckCompleter;
  bool _isActive = false;
  bool _everListened = false;
  String _currentLocale = 'en-US';
  String? _selectedAudioInputDeviceId;
  String _selectedAudioInputDeviceLabel = 'System default microphone';
  List<SttAudioInputDevice> _audioInputDevices = const [];
  int _sessionSequence = 0;
  String _sessionToken = '';
  int _port = _defaultPort;
  final Set<SttBrowserLifecyclePhase> _reportedLifecyclePhases = {};
  final SttSpeechEvidenceGate _speechEvidence = SttSpeechEvidenceGate();
  Future<void> _lifecycleOperationTail = Future<void>.value();

  @override
  Future<SpeechStartResult> start({String? localeId}) {
    return _serializeLifecycleOperation(() => _start(localeId: localeId));
  }

  Future<SpeechStartResult> _start({String? localeId}) async {
    _isActive = false;
    await _stopServer();
    _isActive = true;
    _everListened = false;
    _currentLocale = (localeId ?? 'en-US').replaceAll('_', '-');
    _sessionSequence++;
    final sessionSequence = _sessionSequence;
    _sessionToken = _createSessionToken();
    final sessionToken = _sessionToken;
    _reportedLifecyclePhases.clear();
    _speechEvidence.reset();

    onDiagnostic?.call(
      '[Browser STT] Starting local server on port $_defaultPort...',
    );

    final router = Router();

    router.get('/', (Request req) {
      if (!_requestMatchesSession(req, sessionToken)) {
        return Response.forbidden('invalid session', headers: _textHeaders);
      }
      return Response.ok(
        _buildHtml(
          _currentLocale,
          _selectedAudioInputDeviceId,
          _selectedAudioInputDeviceLabel,
        ),
        headers: _htmlHeaders(sessionToken),
      );
    });

    router.get('/ws', (Request request) {
      if (!_isActive ||
          !_requestMatchesSession(request, sessionToken) ||
          sessionSequence != _sessionSequence ||
          sessionToken != _sessionToken ||
          !_requestHasExpectedOrigin(request)) {
        onDiagnostic?.call(
          '[Browser STT] rejected invalid or stale browser session',
        );
        return Response.forbidden('stale session', headers: _textHeaders);
      }

      return webSocketHandler((WebSocketChannel channel) {
        if (!_matchesCurrentBrowserSession(
          sessionSequence: sessionSequence,
          sessionToken: sessionToken,
        )) {
          unawaited(channel.sink.close().then<void>((_) {}));
          return;
        }
        final previousClient = _wsClient;
        _wsClient = channel;
        if (previousClient != null && previousClient != channel) {
          try {
            previousClient.sink.close();
          } catch (error) {
            _reportAdapterFailure(
              'closeStaleSocket',
              error,
              'failed to close stale browser socket',
            );
          }
        }
        onDiagnostic?.call('[Browser STT] browser host connected');

        channel.stream.listen(
          (message) {
            if (_sessionSequence != sessionSequence ||
                _sessionToken != sessionToken ||
                _wsClient != channel) {
              return;
            }
            try {
              final data =
                  jsonDecode(message as String) as Map<String, dynamic>;
              final type = data['type'] as String? ?? '';
              if (type == 'closeAck') {
                final completer = _closeAckCompleter;
                if (completer != null && !completer.isCompleted) {
                  completer.complete();
                }
                return;
              }
              if (!_isActive) return;
              final lifecycle = SttBrowserLifecycleEvent.fromBrowserMessage(
                data,
              );
              if (lifecycle != null) {
                _handleBrowserLifecycleEvent(
                  lifecycle,
                  sessionSequence: sessionSequence,
                  sessionToken: sessionToken,
                  channel: channel,
                );
              }
              switch (type) {
                case 'devices':
                  final rawDevices = data['devices'];
                  if (rawDevices is List) {
                    final devices =
                        rawDevices
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
                  // Kept for compatibility with an already-loaded older page.
                  break;
                case 'result':
                  if (!_speechEvidence.acceptsResult) break;
                  final words = data['words'] as String? ?? '';
                  final isFinal = data['isFinal'] as bool? ?? false;
                  if (words.trim().isNotEmpty) {
                    onResult?.call(SpeechResult(words, isFinal));
                    onRuntimeHealth?.call(
                      SttRuntimeHealth(
                        type: 'productiveResult',
                        listening: _everListened,
                        locale: _currentLocale,
                      ),
                    );
                  }
                  break;
                case 'speechStart':
                  _speechEvidence.speechStarted();
                  break;
                case 'speechEnd':
                  _speechEvidence.speechEnded();
                  break;
                case 'speechReset':
                  _speechEvidence.reset();
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
                  onDiagnostic?.call('[Browser STT] Input ready');
                  break;
                case 'meterUnavailable':
                  onDiagnostic?.call(
                    '[Browser STT] Microphone opened, but browser audio metering is suspended.',
                  );
                  break;
                case 'lifecycle':
                  break;
                case 'watchdogRestart':
                  final reason = data['reason'] as String? ?? 'stale';
                  final ageMs = (data['ageMs'] as num?)?.toInt() ?? 0;
                  onRuntimeHealth?.call(
                    SttRuntimeHealth(
                      type: 'watchdogRestart',
                      listening: true,
                      locale: _currentLocale,
                      ageMs: ageMs,
                      failures: (data['failures'] as num?)?.toInt() ?? 0,
                    ),
                  );
                  onDiagnostic?.call(
                    '[Browser STT] Renewing recognizer health lease after ${ageMs ~/ 1000}s ($reason)',
                  );
                  break;
                case 'heartbeat':
                  onRuntimeHealth?.call(
                    SttRuntimeHealth(
                      type: 'heartbeat',
                      listening: data['listening'] as bool? ?? false,
                      locale: data['locale'] as String? ?? _currentLocale,
                      ageMs: (data['ageMs'] as num?)?.toInt() ?? 0,
                      failures: (data['failures'] as num?)?.toInt() ?? 0,
                    ),
                  );
                  break;
                case 'error':
                  final err = sanitizeSttBrowserErrorCode(data['error']);
                  if (lifecycle != null) break;
                  onRuntimeHealth?.call(
                    SttRuntimeHealth(
                      type: 'error',
                      listening: _everListened,
                      locale: _currentLocale,
                      failures: 0,
                      error: err,
                    ),
                  );
                  if (err == 'input-device-missing') {
                    onDiagnostic?.call(
                      '[Browser STT] Selected microphone unavailable; using system default.',
                    );
                  } else if (err == 'input-device-failed') {
                    onDiagnostic?.call(
                      '[Browser STT] Could not open selected microphone; using system default.',
                    );
                  } else if (err != 'aborted' && err != 'no-speech') {
                    onDiagnostic?.call('[Browser STT] error: $err');
                  }
                  break;
              }
            } catch (error) {
              _reportAdapterFailure(
                'malformedMessage',
                error,
                'ignored malformed browser message',
              );
            }
          },
          onDone: () {
            final wasCurrentClient = _matchesCurrentBrowserSession(
              sessionSequence: sessionSequence,
              sessionToken: sessionToken,
              channel: channel,
            );
            if (_isActive && wasCurrentClient) {
              _emitBrowserLifecycle(
                const SttBrowserLifecycleEvent(
                  SttBrowserLifecyclePhase.disconnected,
                ),
              );
            }
            if (wasCurrentClient) {
              _wsClient = null;
            }
            if (_isActive && wasCurrentClient) {
              onDiagnostic?.call('[Browser STT] browser host disconnected');
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
        message:
            'Could not start speech-to-text server on ports '
            '$_defaultPort-$_maxFallbackPort: $e',
      );
    }

    onDiagnostic?.call(
      '[Browser STT] browser host ready on localhost:$_port '
      '(session $sessionSequence)',
    );

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
      _wsClient?.sink.add(
        jsonEncode({'type': 'setLocale', 'locale': normalized}),
      );
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
    _selectedAudioInputDeviceLabel =
        (label == null || label.trim().isEmpty)
            ? 'System default microphone'
            : label.trim();
    onDiagnostic?.call(
      normalized == null
          ? '[Browser STT] Using system default microphone'
          : '[Browser STT] Requested configured microphone',
    );
    try {
      _wsClient?.sink.add(
        jsonEncode({
          'type': 'setAudioInputDevice',
          'deviceId': normalized ?? '',
          'label': _selectedAudioInputDeviceLabel,
        }),
      );
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
    if (client != null) {
      final closeAck = Completer<void>();
      _closeAckCompleter = closeAck;
      try {
        client.sink.add(jsonEncode({'type': 'close'}));
        await closeAck.future.timeout(const Duration(milliseconds: 350));
      } on TimeoutException {
        onDiagnostic?.call(
          '[Browser STT] close acknowledgement timed out; forcing shutdown',
        );
      } catch (error) {
        _reportAdapterFailure(
          'requestClose',
          error,
          'failed to request browser shutdown',
        );
      } finally {
        if (identical(_closeAckCompleter, closeAck)) {
          _closeAckCompleter = null;
        }
      }
      _wsClient = null;
      try {
        await client.sink.close();
      } catch (error) {
        _reportAdapterFailure(
          'closeSocket',
          error,
          'failed to close browser socket',
        );
      }
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
    _speechEvidence.reset();
  }

  Future<T> _serializeLifecycleOperation<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _lifecycleOperationTail = _lifecycleOperationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _reportAdapterFailure(String type, Object error, String message) {
    onDiagnostic?.call('[Browser STT] $message: ${error.runtimeType}');
    onRuntimeHealth?.call(
      SttRuntimeHealth(
        type: 'adapterFailure.$type',
        listening: _isActive,
        locale: _currentLocale,
        failures: 1,
        error: 'adapter-failure:${error.runtimeType}',
      ),
    );
  }

  bool _matchesCurrentBrowserSession({
    required int sessionSequence,
    required String sessionToken,
    WebSocketChannel? channel,
  }) {
    return _isActive &&
        sessionSequence == _sessionSequence &&
        sessionToken == _sessionToken &&
        (channel == null || _wsClient == channel);
  }

  void _handleBrowserLifecycleEvent(
    SttBrowserLifecycleEvent event, {
    required int sessionSequence,
    required String sessionToken,
    required WebSocketChannel channel,
  }) {
    if (!_matchesCurrentBrowserSession(
      sessionSequence: sessionSequence,
      sessionToken: sessionToken,
      channel: channel,
    )) {
      return;
    }

    if (event.phase == SttBrowserLifecyclePhase.recognizerListening &&
        !_everListened) {
      _everListened = true;
      onStatusChange?.call(SpeechStatus.listening);
    }
    final emitted = _emitBrowserLifecycle(event);
    if (emitted && event.phase == SttBrowserLifecyclePhase.permissionDenied) {
      onError?.call(
        'Microphone blocked in the speech browser.\n'
        'Open Windows microphone settings and allow microphone '
        'access for desktop apps.',
      );
    }
  }

  bool _emitBrowserLifecycle(SttBrowserLifecycleEvent event) {
    final repeatable = event.phase == SttBrowserLifecyclePhase.network;
    if (!repeatable && !_reportedLifecyclePhases.add(event.phase)) return false;

    onRuntimeHealth?.call(
      event.toRuntimeHealth(locale: _currentLocale, hasListened: _everListened),
    );
    onDiagnostic?.call('[Browser STT] lifecycle ${event.phase.name}');
    return true;
  }

  Future<HttpServer> _serveOnAvailablePort(Handler handler) async {
    Object? lastError;
    for (var port = _defaultPort; port <= _maxFallbackPort; port++) {
      try {
        final server = await shelf_io.serve(handler, 'localhost', port);
        _port = port;
        if (port != _defaultPort) {
          onDiagnostic?.call(
            '[Browser STT] default port busy; using fallback port $port',
          );
        }
        return server;
      } catch (e) {
        lastError = e;
        onDiagnostic?.call('[Browser STT] port $port unavailable: $e');
      }
    }
    throw lastError ?? StateError('No speech-to-text ports available');
  }

  static String _createSessionToken() {
    final bytes = List<int>.generate(
      24,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _requestMatchesSession(Request request, String expectedToken) {
    final requestedToken = request.url.queryParameters['session'] ?? '';
    final requestedHost = request.requestedUri.host.toLowerCase();
    return requestedHost == 'localhost' &&
        requestedToken.isNotEmpty &&
        requestedToken == expectedToken;
  }

  bool _requestHasExpectedOrigin(Request request) {
    final origin = request.headers['origin'];
    return origin == 'http://localhost:$_port';
  }

  Map<String, String> _htmlHeaders(String nonce) {
    return {
      ..._baseHtmlHeaders,
      'content-security-policy':
          "default-src 'none'; base-uri 'none'; form-action 'none'; "
          "frame-ancestors 'none'; object-src 'none'; img-src 'none'; "
          "font-src 'none'; media-src 'none'; worker-src 'none'; "
          "script-src 'nonce-$nonce'; style-src 'nonce-$nonce'; "
          'connect-src ws://localhost:$_port',
      'permissions-policy':
          'camera=(), display-capture=(), geolocation=(), microphone=(self)',
    };
  }

  @override
  Future<void> stop() {
    return _serializeLifecycleOperation(_stop);
  }

  Future<void> _stop() async {
    _isActive = false;
    await _stopServer();
    onStatusChange?.call(SpeechStatus.idle);
  }

  @override
  bool get isListening => _isActive;

  @override
  String get platformName => 'Browser Online';

  /// URL loaded by the selected browser host (the STT page itself).
  @override
  String? get sttWebViewUrl =>
      _server != null
          ? Uri(
            scheme: 'http',
            host: 'localhost',
            port: _port,
            path: '/',
            queryParameters: {'session': _sessionToken},
          ).toString()
          : null;
}
