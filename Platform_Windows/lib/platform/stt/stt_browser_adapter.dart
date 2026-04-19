import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, HttpServer, InternetAddress, Process, ProcessStartMode;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Windows STT via browser Web Speech API.
///
/// Launches Edge/Chrome completely hidden (Win32 ShowWindow via PowerShell)
/// to run Web Speech API and streams results back to Flutter via WebSocket.
/// A second /display + /display-ws endpoint is served for the embedded
/// WebView2 debug panel — no mic access required in the WebView.
class SttBrowserAdapter extends AbstractSttService {
  static const int _port = 8082;

  HttpServer? _server;
  WebSocketChannel? _wsClient;
  final List<WebSocketChannel> _displayClients = [];
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

    // STT page — loaded by external Edge/Chrome (hidden)
    router.get('/', (Request req) {
      return Response.ok(
        _buildSttHtml(_currentLocale),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    // Display page — loaded by embedded WebView2 (no mic needed)
    router.get('/display', (Request req) {
      return Response.ok(
        _buildDisplayHtml(),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    // STT WebSocket — browser sends recognition results here
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
                // Only fire onStatusChange once (not on every restart)
                if (!_everListened) {
                  _everListened = true;
                  onStatusChange?.call(SpeechStatus.listening);
                  onDiagnostic?.call('🎤 [Browser STT] Web Speech API active — speak now');
                }
                _pushToDisplay(data);
                break;
              case 'result':
                final words = data['words'] as String? ?? '';
                final isFinal = data['isFinal'] as bool? ?? false;
                if (words.isNotEmpty) {
                  onResult?.call(SpeechResult(words, isFinal));
                  _pushToDisplay(data);
                }
                break;
              case 'level':
                final level = (data['level'] as num?)?.toDouble() ?? 0.0;
                onSoundLevelChange?.call(level);
                _pushToDisplay(data);
                break;
              case 'error':
                final err = data['error'] as String? ?? 'unknown';
                // Suppress 'aborted' and 'no-speech' — normal restart chatter
                if (err == 'not-allowed') {
                  onError?.call('Microphone blocked in browser — allow mic access when prompted.');
                } else if (err != 'aborted' && err != 'no-speech') {
                  onDiagnostic?.call('⚠️ [Browser STT] error: $err');
                }
                _pushToDisplay(data);
                break;
            }
          } catch (_) {}
        },
        onDone: () {
          if (_isActive) onDiagnostic?.call('⚠️ [Browser STT] Browser disconnected');
        },
      );
    }));

    // Display WebSocket — embedded WebView2 subscribes here (read-only)
    router.get('/display-ws', webSocketHandler((WebSocketChannel channel) {
      _displayClients.add(channel);
      channel.stream.listen((_) {}, onDone: () => _displayClients.remove(channel));
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

    onDiagnostic?.call('🌐 [Browser STT] Server ready at http://localhost:$_port/');

    _launchBrowser();
    _hideBrowserWindow(); // runs its own 6s sleep inside the PS1

    return SpeechStartResult(
      success: true,
      actualLocale: _currentLocale,
      requestedLocale: localeId,
    );
  }

  /// Send a locale-switch message to the running browser — no restart needed.
  @override
  void setLocale(String locale) {
    final normalized = locale.replaceAll('_', '-');
    if (normalized == _currentLocale) return;
    _currentLocale = normalized;
    try {
      _wsClient?.sink.add(jsonEncode({'type': 'setLocale', 'locale': normalized}));
    } catch (_) {}
  }

  // ── Browser launch + window hiding ─────────────────────────────────────────

  void _launchBrowser() {
    const browsers = [
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    ];
    String? browserPath;
    for (final path in browsers) {
      if (File(path).existsSync()) { browserPath = path; break; }
    }
    if (browserPath == null) {
      onDiagnostic?.call('⚠️ [Browser STT] Edge/Chrome not found — open http://localhost:$_port/ manually');
      return;
    }

    Process.start(
      browserPath,
      ['--app=http://localhost:$_port/', '--no-first-run', '--disable-features=TranslateUI'],
      mode: ProcessStartMode.detached,
    ).then((_) {
      onDiagnostic?.call('🌐 [Browser STT] Browser launched — hiding window...');
    }).catchError((_) {
      onDiagnostic?.call('⚠️ [Browser STT] Failed to launch browser');
    });
  }

  /// Write a temp PowerShell script that finds Edge/Chrome windows whose
  /// title contains "AutoTeleprompter" and hides them via Win32 ShowWindow.
  /// Uses Get-Process (not FindWindow) so it works regardless of whether
  /// Edge appends "- Microsoft Edge" to the title.
  Future<void> _hideBrowserWindow() async {
    try {
      final ps1 = File('${Directory.systemTemp.path}\\at_stt_hide.ps1');
      await ps1.writeAsString(r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class W32 {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
# Wait for Edge to fully initialize and set the window title
$maxAttempts = 8
$attempt = 0
$hidden = $false
Start-Sleep -Seconds 4
while ($attempt -lt $maxAttempts -and -not $hidden) {
    $procs = Get-Process -Name msedge,chrome -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $p.Refresh()
        if ($p.MainWindowTitle -like "*AutoTeleprompter*" -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
            [W32]::ShowWindow($p.MainWindowHandle, 0)
            $hidden = $true
        }
    }
    if (-not $hidden) { Start-Sleep -Seconds 1 }
    $attempt++
}
Remove-Item $PSCommandPath -Force -ErrorAction SilentlyContinue
''');

      await Process.start(
        'powershell.exe',
        ['-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1.path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  void _pushToDisplay(Map<String, dynamic> data) {
    if (_displayClients.isEmpty) return;
    final encoded = jsonEncode(data);
    for (final client in List.of(_displayClients)) {
      try { client.sink.add(encoded); } catch (_) {}
    }
  }

  Future<void> _stopServer() async {
    try { _wsClient?.sink.close(); } catch (_) {}
    for (final c in List.of(_displayClients)) {
      try { c.sink.close(); } catch (_) {}
    }
    _displayClients.clear();
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

  @override
  String? get sttWebViewUrl => _server != null ? 'http://localhost:$_port/display' : null;

  @override
  bool get requiresImmediateListeningFlag => true;

  // ── STT page (external browser, hidden after init) ──────────────────────────

  String _buildSttHtml(String locale) => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AutoTeleprompter \u2014 Mic</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0d0d0d;color:#eee;font-family:-apple-system,sans-serif;
       display:flex;flex-direction:column;align-items:center;justify-content:center;
       min-height:100vh;gap:18px;padding:20px}
  .mic{width:28px;height:28px;border-radius:50%;background:#333;transition:background .3s}
  .mic.on{background:#22c55e;box-shadow:0 0 12px #22c55e88;animation:pulse 1s infinite}
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
let currentLocale='$locale';
let consecutiveFails=0;   // counts rapid aborts to throttle restart speed
let lastNonAbortError=''; // tracks the last real error type

ws.onopen=()=>{status.textContent='Starting microphone...';startRec(currentLocale);};
ws.onclose=()=>{status.textContent='Session ended.';dot.classList.remove('on');if(rec)rec.abort();};
ws.onmessage=(e)=>{
  const d=JSON.parse(e.data);
  if(d.type==='setLocale'&&d.locale!==currentLocale){
    currentLocale=d.locale;
    consecutiveFails=0;
    status.textContent='Switching to '+d.locale+'...';
    if(rec)rec.abort();
    setTimeout(()=>startRec(currentLocale),400);
  }
};

function send(o){if(ws.readyState===1)ws.send(JSON.stringify(o));}

// Restart delay with exponential back-off for crash loops.
// Normal restart: 300ms. After 3+ quick aborts: grows up to 8s.
function restartDelay(){
  if(consecutiveFails<=2) return 300;
  return Math.min(300*Math.pow(2,consecutiveFails-2),8000);
}

function startRec(locale){
  const SR=window.SpeechRecognition||window.webkitSpeechRecognition;
  if(!SR){err.textContent='Web Speech API not available. Please use Microsoft Edge or Google Chrome.';return;}
  rec=new SR();
  rec.lang=locale;
  rec.continuous=true;
  rec.interimResults=true;

  rec.onstart=()=>{
    consecutiveFails=0;
    dot.classList.add('on');
    status.textContent='Listening ('+locale+')...';
    send({type:'listening'});
  };
  rec.onresult=(e)=>{
    consecutiveFails=0;
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
      err.textContent='Microphone denied. Click the lock icon and allow microphone.';
      dot.classList.remove('on');
    } else if(e.error==='aborted'){
      consecutiveFails++;
    } else if(e.error!=='no-speech'){
      lastNonAbortError=e.error;
      consecutiveFails++;
    }
  };
  rec.onend=()=>{
    dot.classList.remove('on');
    if(ws.readyState===1) setTimeout(()=>startRec(currentLocale),restartDelay());
  };
  try{rec.start();}catch(ex){consecutiveFails++;setTimeout(()=>startRec(currentLocale),restartDelay());}
}
</script>
</body>
</html>
''';

  // ── Display page (embedded WebView2 — no mic, shows live results) ──────────

  String _buildDisplayHtml() => '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>STT Display</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0a0a0a;color:#eee;font-family:-apple-system,sans-serif;
       display:flex;flex-direction:column;align-items:center;justify-content:center;
       height:100vh;gap:10px;padding:12px;overflow:hidden}
  .dot{width:10px;height:10px;border-radius:50%;background:#555;flex-shrink:0}
  .dot.on{background:#22c55e;box-shadow:0 0 8px #22c55e88;animation:p 1s infinite}
  @keyframes p{0%,100%{opacity:1}50%{opacity:.4}}
  #row{display:flex;align-items:center;gap:8px}
  #status{font-size:11px;color:#666}
  #bar{height:6px;width:100%;max-width:200px;background:#222;border-radius:3px;overflow:hidden}
  #fill{height:100%;width:0%;background:#22c55e;border-radius:3px;transition:width .1s}
  #words{font-size:13px;color:#22c55e;text-align:center;max-width:280px;
         min-height:36px;line-height:1.4;word-break:break-word}
</style>
</head>
<body>
<div id="row"><div class="dot" id="dot"></div><div id="status">Connecting...</div></div>
<div id="bar"><div id="fill"></div></div>
<div id="words"></div>
<script>
const dot=document.getElementById('dot');
const status=document.getElementById('status');
const fill=document.getElementById('fill');
const words=document.getElementById('words');

function connect(){
  const ws=new WebSocket('ws://localhost:$_port/display-ws');
  ws.onopen=()=>status.textContent='Waiting for speech...';
  ws.onclose=()=>{dot.classList.remove('on');status.textContent='Disconnected';setTimeout(connect,2000);};
  ws.onmessage=(e)=>{
    const d=JSON.parse(e.data);
    if(d.type==='listening'){dot.classList.add('on');status.textContent='Listening...';}
    if(d.type==='result'){words.textContent=d.words;}
    if(d.type==='level'){fill.style.width=Math.round(d.level*100)+'%';}
    if(d.type==='error'&&d.error!=='no-speech'&&d.error!=='aborted'){
      status.textContent='Error: '+d.error;dot.classList.remove('on');
    }
  };
}
connect();
</script>
</body>
</html>
''';
}
