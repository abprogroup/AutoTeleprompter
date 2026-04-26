import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpServer, InternetAddress;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Windows STT via Web Speech API running inside the embedded WebView2.
///
/// Serves a local HTML page that runs SpeechRecognition and sends results
/// back via WebSocket. The page is loaded directly by the WebviewController
/// so no external browser is involved.
///
/// Microphone access is pre-granted by writing the WebView2 Preferences file
/// before the controller is initialized (done in TeleprompterScreen).
class SttBrowserAdapter extends AbstractSttService {
  static const int _port = 8082;

  HttpServer? _server;
  WebSocketChannel? _wsClient;
  bool _isActive = false;
  bool _everListened = false;
  String _currentLocale = 'en-US';

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    _isActive = true;
    _everListened = false;
    _currentLocale = (localeId ?? 'en-US').replaceAll('_', '-');

    onDiagnostic?.call('🌐 [Browser STT] Starting local server on port $_port...');

    await _stopServer();

    final router = Router();

    router.get('/', (Request req) {
      return Response.ok(
        _buildHtml(_currentLocale),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    router.get('/ws', webSocketHandler((WebSocketChannel channel) {
      _wsClient = channel;
      onDiagnostic?.call('🔗 [Browser STT] WebView connected');

      channel.stream.listen(
        (message) {
          if (!_isActive) return;
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String? ?? '';
            switch (type) {
              case 'listening':
                if (!_everListened) {
                  _everListened = true;
                  onStatusChange?.call(SpeechStatus.listening);
                  onDiagnostic?.call('🎤 [Browser STT] Web Speech API active — speak now');
                }
                break;
              case 'result':
                final words = data['words'] as String? ?? '';
                final isFinal = data['isFinal'] as bool? ?? false;
                if (words.isNotEmpty) onResult?.call(SpeechResult(words, isFinal));
                break;
              case 'level':
                final level = (data['level'] as num?)?.toDouble() ?? 0.0;
                onSoundLevelChange?.call(level);
                break;
              case 'error':
                final err = data['error'] as String? ?? 'unknown';
                if (err == 'not-allowed') {
                  onError?.call(
                    'Microphone blocked in WebView2.\n'
                    'Grant mic access once: open http://localhost:$_port/ in Edge, '
                    'allow microphone, then restart the session.');
                } else if (err != 'aborted' && err != 'no-speech') {
                  onDiagnostic?.call('⚠️ [Browser STT] error: $err');
                }
                break;
            }
          } catch (_) {}
        },
        onDone: () {
          if (_isActive) onDiagnostic?.call('⚠️ [Browser STT] WebView disconnected');
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

    onDiagnostic?.call('🌐 [Browser STT] WebView ready at http://localhost:$_port/');

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
    try {
      _wsClient?.sink.add(jsonEncode({'type': 'setLocale', 'locale': normalized}));
    } catch (_) {}
  }

  Future<void> _stopServer() async {
    try { _wsClient?.sink.close(); } catch (_) {}
    try { await _server?.close(force: true); } catch (_) {}
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

  /// URL loaded by the embedded WebviewController (the STT page itself).
  @override
  String? get sttWebViewUrl => _server != null ? 'http://localhost:$_port/' : null;

  @override
  bool get requiresImmediateListeningFlag => true;

  String _buildHtml(String locale) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AutoTeleprompter \u2014 Mic</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0d0d0d;color:#eee;font-family:-apple-system,sans-serif;
       display:flex;flex-direction:column;align-items:center;justify-content:center;
       height:100vh;gap:12px;padding:16px;overflow:hidden}
  .dot{width:14px;height:14px;border-radius:50%;background:#333;flex-shrink:0}
  .dot.on{background:#22c55e;box-shadow:0 0 10px #22c55e88;animation:p 1s infinite}
  @keyframes p{0%,100%{opacity:1}50%{opacity:.4}}
  #row{display:flex;align-items:center;gap:8px}
  #status{font-size:12px;color:#888}
  #bar{height:5px;width:140px;background:#222;border-radius:3px;overflow:hidden}
  #fill{height:100%;width:0%;background:#22c55e;border-radius:3px;transition:width .1s}
  #words{font-size:14px;color:#22c55e;text-align:center;max-width:280px;
         min-height:40px;line-height:1.4;word-break:break-word}
  #err{color:#ef4444;font-size:11px;text-align:center;max-width:260px;line-height:1.4}
</style>
</head>
<body>
<div id="row"><div class="dot" id="dot"></div><div id="status">Connecting...</div></div>
<div id="bar"><div id="fill"></div></div>
<div id="words"></div>
<div id="err"></div>
<script>
const ws=new WebSocket('ws://localhost:$_port/ws');
const dot=document.getElementById('dot');
const status=document.getElementById('status');
const fill=document.getElementById('fill');
const words=document.getElementById('words');
const err=document.getElementById('err');
let rec;
let currentLocale='$locale';
let consecutiveFails=0;

ws.onopen=()=>{status.textContent='Starting microphone...';startRec(currentLocale);};
ws.onclose=()=>{status.textContent='Session ended.';dot.classList.remove('on');if(rec)rec.abort();};
ws.onmessage=(e)=>{
  const d=JSON.parse(e.data);
  if(d.type==='setLocale'&&d.locale!==currentLocale){
    currentLocale=d.locale;consecutiveFails=0;
    status.textContent='Switching to '+d.locale+'...';
    if(rec)rec.abort();
    setTimeout(()=>startRec(currentLocale),400);
  }
};

function send(o){if(ws.readyState===1)ws.send(JSON.stringify(o));}

function restartDelay(){
  if(consecutiveFails<=2)return 300;
  return Math.min(300*Math.pow(2,consecutiveFails-2),8000);
}

function startRec(locale){
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){err.textContent='Web Speech API not available in this browser.';return;}
  rec=new SR();
  rec.lang=locale;rec.continuous=true;rec.interimResults=true;
  rec.onstart=()=>{
    consecutiveFails=0;dot.classList.add('on');
    status.textContent='Listening ('+locale+')...';send({type:'listening'});
  };
  rec.onresult=(e)=>{
    consecutiveFails=0;
    for(let i=e.resultIndex;i<e.results.length;i++){
      const t=e.results[i][0].transcript;
      const f=e.results[i].isFinal;
      send({type:'result',words:t,isFinal:f});words.textContent=t;
    }
    send({type:'level',level:0.65});fill.style.width='65%';
  };
  rec.onspeechstart=()=>{send({type:'level',level:0.7});fill.style.width='70%';};
  rec.onspeechend=()=>{send({type:'level',level:0.1});fill.style.width='10%';};
  rec.onerror=(e)=>{
    send({type:'error',error:e.error});
    if(e.error==='not-allowed'){
      err.textContent='Mic blocked — grant permission and restart session.';
      dot.classList.remove('on');return;
    }
    if(e.error==='aborted')consecutiveFails++;
    else if(e.error!=='no-speech')consecutiveFails++;
  };
  rec.onend=()=>{
    dot.classList.remove('on');fill.style.width='0%';
    if(ws.readyState===1)setTimeout(()=>startRec(currentLocale),restartDelay());
  };
  try{rec.start();}catch(ex){consecutiveFails++;setTimeout(()=>startRec(currentLocale),restartDelay());}
}
</script>
</body>
</html>
''';
}
