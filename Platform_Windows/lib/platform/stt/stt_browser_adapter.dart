import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Windows STT via browser Web Speech API.
///
/// Opens a local page in Edge/Chrome that runs Web Speech API and streams
/// results back to the Flutter app via WebSocket. This bypasses the broken
/// Windows.Media.SpeechRecognition WinRT API which requires "Online speech
/// recognition" to be enabled in Windows Privacy settings.
class SttBrowserAdapter extends AbstractSttService {
  static const int _port = 8082;

  HttpServer? _server;
  WebSocketChannel? _wsClient;
  bool _isActive = false;

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    _isActive = true;
    final locale = (localeId ?? 'en-US').replaceAll('_', '-');

    onDiagnostic?.call('🌐 [Browser STT] Starting local server on port $_port...');

    await _stopServer();

    final router = Router();

    router.get('/', (Request req) {
      return Response.ok(
        _buildHtml(locale),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    router.get('/ws', webSocketHandler((WebSocketChannel channel) {
      _wsClient = channel;
      onDiagnostic?.call('🔗 [Browser STT] Browser connected');

      channel.stream.listen(
        (message) {
          if (!_isActive) return;
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String? ?? '';
            switch (type) {
              case 'listening':
                onStatusChange?.call(SpeechStatus.listening);
                onDiagnostic?.call('🎤 [Browser STT] Web Speech API active — speak now');
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
              case 'error':
                final err = data['error'] as String? ?? 'unknown';
                if (err == 'not-allowed') {
                  onError?.call('Microphone blocked in browser. Click the address bar lock icon → allow microphone.');
                } else {
                  onDiagnostic?.call('⚠️ [Browser STT] error: $err');
                }
                break;
            }
          } catch (_) {}
        },
        onDone: () {
          if (_isActive) onDiagnostic?.call('⚠️ [Browser STT] Browser disconnected');
        },
      );
    }));

    try {
      _server = await shelf_io.serve(router.call, 'localhost', _port);
    } catch (e) {
      _isActive = false;
      return SpeechStartResult(
        success: false,
        message: 'Could not start STT server on port $_port: $e',
      );
    }

    onDiagnostic?.call('🌐 [Browser STT] Opening browser — please allow microphone if prompted');
    await Process.run('cmd', ['/c', 'start', 'http://localhost:$_port/'], runInShell: true);

    return SpeechStartResult(
      success: true,
      actualLocale: locale,
      requestedLocale: localeId,
    );
  }

  Future<void> _stopServer() async {
    try {
      _wsClient?.sink.close();
    } catch (_) {}
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _wsClient = null;
    _server = null;
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
  String get platformName => 'Windows';

  @override
  // We call onStatusChange(listening) when the browser connects,
  // so set this to true to show listening state immediately.
  bool get requiresImmediateListeningFlag => true;

  String _buildHtml(String locale) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AutoTeleprompter — Mic</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0d0d0d;color:#eee;font-family:-apple-system,sans-serif;
       display:flex;flex-direction:column;align-items:center;justify-content:center;
       min-height:100vh;gap:18px;padding:20px}
  .mic{width:28px;height:28px;border-radius:50%;background:#333;
       transition:background .3s}
  .mic.on{background:#22c55e;box-shadow:0 0 12px #22c55e88;
           animation:pulse 1s ease-in-out infinite}
  @keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}
  #status{font-size:13px;color:#888}
  #words{font-size:17px;color:#22c55e;max-width:320px;text-align:center;min-height:48px}
  #err{color:#ef4444;font-size:12px;max-width:300px;text-align:center;line-height:1.5}
</style>
</head>
<body>
<div class="mic" id="dot"></div>
<div id="status">Connecting to AutoTeleprompter...</div>
<div id="words"></div>
<div id="err"></div>
<script>
const ws=new WebSocket('ws://localhost:$_port/ws');
const dot=document.getElementById('dot');
const status=document.getElementById('status');
const words=document.getElementById('words');
const err=document.getElementById('err');
let rec;

ws.onopen=()=>{status.textContent='Starting microphone...';startRec();};
ws.onclose=()=>{status.textContent='Session ended.';dot.classList.remove('on');if(rec)rec.abort();};

function send(o){if(ws.readyState===1)ws.send(JSON.stringify(o));}

function startRec(){
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){
    err.textContent='Web Speech API not available. Please use Microsoft Edge or Google Chrome.';
    return;
  }
  rec=new SR();
  rec.lang='$locale';
  rec.continuous=true;
  rec.interimResults=true;

  rec.onstart=()=>{dot.classList.add('on');status.textContent='Listening...';send({type:'listening'});};
  rec.onresult=(e)=>{
    for(let i=e.resultIndex;i<e.results.length;i++){
      const t=e.results[i][0].transcript;
      const f=e.results[i].isFinal;
      send({type:'result',words:t,isFinal:f});
      words.textContent=t;
    }
    send({type:'level',level:0.65});
  };
  rec.onspeechstart=()=>send({type:'level',level:0.7});
  rec.onspeechend=()=>send({type:'level',level:0.1});
  rec.onerror=(e)=>{
    send({type:'error',error:e.error});
    if(e.error==='not-allowed'){
      err.textContent='Microphone denied. Click the lock icon in the browser address bar and allow microphone.';
      dot.classList.remove('on');
    } else if(e.error!=='aborted'&&e.error!=='no-speech'){
      setTimeout(startRec,1000);
    }
  };
  rec.onend=()=>{if(ws.readyState===1){dot.classList.remove('on');setTimeout(startRec,200);}};
  try{rec.start();}catch(e){setTimeout(startRec,500);}
}
</script>
</body>
</html>
''';
}
