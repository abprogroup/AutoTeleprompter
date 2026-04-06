import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

class RemoteControlService {
  HttpServer? _server;
  final _onCommand = StreamController<String>.broadcast();
  Stream<String> get onCommand => _onCommand.stream;

  Future<void> start() async {
    final router = Router();

    router.get('/ws', webSocketHandler((WebSocketChannel webSocket) {
      webSocket.stream.listen((message) {
        debugPrint('Remote Command: $message');
        _onCommand.add(message.toString());
      });
    }));

    router.get('/', (Request request) {
      return Response.ok(_html, headers: {'content-type': 'text/html'});
    });

    final handler = Pipeline().addMiddleware(logRequests()).addHandler(router.call);
    
    _server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
    debugPrint('V3 Remote Server active at http://${_server!.address.address}:8080');
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  static const String _html = '''
<!DOCTYPE html>
<html>
<head>
    <title>V3 REMOTE SUITE</title>
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
    </style>
</head>
<body>
    <div class="brand">V3 PROFESSIONAL SUITE</div>
    
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

    <div id="log" class="status">Connecting...</div>

    <script>
        let ws;
        function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws');
            ws.onopen = () => document.getElementById('log').innerText = 'CONNECTED TO BROADCASTER';
            ws.onclose = () => { document.getElementById('log').innerText = 'OFFLINE: RECONNECTING...'; setTimeout(connect, 2000); };
        }
        function send(cmd) { if(ws && ws.readyState === 1) ws.send(cmd); }
        function setMode(mode) {
            send(mode);
            document.getElementById('btn_manual').classList.toggle('active', mode === 'MODE_MANUAL');
            document.getElementById('btn_auto').classList.toggle('active', mode === 'MODE_AUTO');
        }
        connect();
    </script>
</body>
</html>
''';
}

final remoteControlProvider = Provider((ref) => RemoteControlService());
