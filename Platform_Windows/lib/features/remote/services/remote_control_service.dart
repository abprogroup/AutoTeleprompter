import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class RemoteControlService {
  static const int defaultPort = 8080;
  static const int maxFallbackPort = 8090;
  static const Set<String> allowedCommands = {
    'TOGGLE',
    'FASTER',
    'SLOWER',
    'RESET',
    'MODE_AUTO',
    'MODE_MANUAL',
  };
  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };
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
  final _onCommand = StreamController<String>.broadcast();
  String _pairingPin = '';
  String _sessionToken = '';
  Stream<String> get onCommand => _onCommand.stream;
  bool get isRunning => _server != null;
  int get port => _server?.port ?? defaultPort;
  String get pairingPin => isRunning ? _pairingPin : '';
  String get localUrl => _remoteUrlForHost('localhost');

  Future<void> start() async {
    if (_server != null) return;
    _pairingPin = _newPairingPin();
    _sessionToken = _newSessionToken();

    final router = Router();
    final wsHandler = webSocketHandler((WebSocketChannel webSocket) {
      webSocket.stream.listen((message) {
        final command = message.toString();
        if (!isAllowedCommand(command)) {
          if (kDebugMode) debugPrint('Rejected remote command: $command');
          webSocket.sink.add(
            jsonEncode({'ok': false, 'error': 'invalid_command'}),
          );
          return;
        }
        if (kDebugMode) debugPrint('Remote Command: $command');
        _onCommand.add(command);
      });
    });

    router.get('/pair', (Request request) {
      final pin = request.url.queryParameters['pin'] ?? '';
      if (pin != _pairingPin) {
        return Response.forbidden(
          jsonEncode({'ok': false, 'error': 'pairing_required'}),
          headers: _jsonHeaders,
        );
      }
      return Response.ok(
        jsonEncode({'ok': true, 'token': _sessionToken}),
        headers: _jsonHeaders,
      );
    });

    router.get('/ws', (Request request) {
      final token = request.url.queryParameters['token'] ?? '';
      if (token != _sessionToken) {
        return Response.forbidden('Pairing required.', headers: _textHeaders);
      }
      return wsHandler(request);
    });

    router.get('/', (Request request) {
      return Response.ok(_html, headers: _htmlHeaders);
    });

    final pipeline = kDebugMode
        ? const Pipeline().addMiddleware(logRequests())
        : const Pipeline();
    final handler = pipeline.addHandler(router.call);

    _server = await _bindAvailablePort(handler);
    if (kDebugMode) {
      debugPrint(
        'V5 Remote Server active at http://${_server!.address.address}:$port',
      );
    }
  }

  Future<HttpServer> _bindAvailablePort(Handler handler) async {
    Object? lastError;
    for (var candidate = defaultPort;
        candidate <= maxFallbackPort;
        candidate++) {
      try {
        return await io.serve(handler, InternetAddress.anyIPv4, candidate);
      } on SocketException catch (error) {
        lastError = error;
        if (kDebugMode) {
          debugPrint(
            'Remote port $candidate unavailable, trying ${candidate + 1}...',
          );
        }
      }
    }
    throw StateError(
      'Unable to start remote control. Ports '
      '$defaultPort-$maxFallbackPort are unavailable. Last error: $lastError',
    );
  }

  Future<String> preferredUrl() async {
    final addresses = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in addresses) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          return _remoteUrlForHost(address.address);
        }
      }
    }
    return localUrl;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _pairingPin = '';
    _sessionToken = '';
  }

  String _remoteUrlForHost(String host) {
    final base = 'http://$host:$port';
    return isRunning ? '$base?pin=$_pairingPin' : base;
  }

  String _newPairingPin() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  String _newSessionToken() {
    final random = Random.secure();
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      32,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  static bool isAllowedCommand(String command) {
    return allowedCommands.contains(command);
  }

  static const String _html = '''
<!DOCTYPE html>
<html>
<head>
    <title>AutoTeleprompter Remote</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        body { background: #0A0A0A; color: white; font-family: -apple-system, system-ui; text-align: center; padding: 20px; margin: 0; }
        .brand { color: #FFBF00; font-weight: 900; letter-spacing: 2px; margin-bottom: 20px; font-size: 20px; }
        .section { margin-bottom: 25px; padding: 15px; background: #111; border-radius: 15px; }
        .label { color: #555; font-size: 10px; font-weight: bold; text-transform: uppercase; margin-bottom: 12px; display: block; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; max-width: 400px; margin: 0 auto; }
        button { 
            background: #1A1A1A; border: 1px solid #333; color: white; padding: 20px 10px; border-radius: 12px; font-size: 14px; font-weight: bold;
            transition: all 0.2s; -webkit-tap-highlight-color: transparent; outline: none;
        }
        button:active { background: #FFBF00; color: black; transform: scale(0.95); }
        .active { background: #FFBF00 !important; color: black !important; border-color: #FFBF00; }
        .full { grid-column: span 2; padding: 25px 10px; }
        .reset { background: #331A1A; color: #FF4444; border-color: #441A1A; }
        .status { margin-top: 20px; color: #444; font-size: 11px; }
        .pair { max-width: 400px; margin: 0 auto 20px; padding: 15px; background: #111; border-radius: 15px; }
        input { width: 100%; box-sizing: border-box; background: #050505; color: white; border: 1px solid #333; border-radius: 10px; padding: 14px; text-align: center; font-size: 22px; letter-spacing: 8px; margin-bottom: 10px; }
        .hidden { display: none; }
    </style>
</head>
<body>
    <div class="brand">AUTOTELEPROMPTER REMOTE</div>

    <div id="pair" class="pair">
        <span class="label">Pairing PIN</span>
        <input id="pin" inputmode="numeric" maxlength="6" placeholder="000000">
        <button class="full" onclick="pair()">PAIR REMOTE</button>
    </div>
    
    <div id="controls" class="hidden">
    <div class="section">
        <span class="label">Operation Mode</span>
        <div class="grid">
            <button id="btn_manual" class="active" onclick="setMode('MODE_MANUAL')">MANUAL SCROLL</button>
            <button id="btn_auto" onclick="setMode('MODE_AUTO')">SPEECH FOLLOW</button>
        </div>
    </div>

    <div class="section">
        <span class="label">Live Controls</span>
        <div class="grid">
            <button class="full" onclick="send('TOGGLE')">START / STOP SESSION</button>
            <button onclick="send('FASTER')">SPEED UP (+)</button>
            <button onclick="send('SLOWER')">SLOW DOWN (-)</button>
            <button class="full reset" onclick="send('RESET')">RESET POSITION</button>
        </div>
    </div>
    </div>

    <div id="log" class="status">Connecting...</div>

    <script>
        let ws;
        let token = '';
        const params = new URLSearchParams(location.search);
        const pinFromUrl = params.get('pin');
        if (pinFromUrl) {
            document.getElementById('pin').value = pinFromUrl;
            pair();
        } else {
            document.getElementById('log').innerText = 'ENTER PAIRING PIN';
        }
        async function pair() {
            const pin = document.getElementById('pin').value.trim();
            if (!pin) return;
            const response = await fetch('/pair?pin=' + encodeURIComponent(pin));
            const data = await response.json().catch(() => ({ ok: false }));
            if (!data.ok || !data.token) {
                document.getElementById('log').innerText = 'PAIRING FAILED';
                return;
            }
            token = data.token;
            document.getElementById('pair').classList.add('hidden');
            document.getElementById('controls').classList.remove('hidden');
            connect();
        }
        function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws?token=' + encodeURIComponent(token));
            ws.onopen = () => document.getElementById('log').innerText = 'CONNECTED TO BROADCASTER';
            ws.onclose = () => { document.getElementById('log').innerText = 'OFFLINE: RECONNECTING...'; setTimeout(connect, 2000); };
        }
        function send(cmd) { if(ws && ws.readyState === 1) ws.send(cmd); }
        function setMode(mode) {
            send(mode);
            document.getElementById('btn_manual').classList.toggle('active', mode === 'MODE_MANUAL');
            document.getElementById('btn_auto').classList.toggle('active', mode === 'MODE_AUTO');
        }
    </script>
</body>
</html>
''';
}

final remoteControlProvider = Provider((ref) => RemoteControlService());
