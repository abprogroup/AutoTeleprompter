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
  String? _selectedAudioInputDeviceId;
  String _selectedAudioInputDeviceLabel = 'System default microphone';
  List<SttAudioInputDevice> _audioInputDevices = const [];
  int _sessionId = 0;

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    _isActive = true;
    _everListened = false;
    _currentLocale = (localeId ?? 'en-US').replaceAll('_', '-');
    _sessionId++;

    onDiagnostic
        ?.call('🌐 [Browser STT] Starting local server on port $_port...');

    await _stopServer();

    final router = Router();

    router.get('/', (Request req) {
      return Response.ok(
        _buildHtml(_currentLocale, _selectedAudioInputDeviceId),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    router.get('/ws', webSocketHandler((WebSocketChannel channel) {
      final previousClient = _wsClient;
      _wsClient = channel;
      if (previousClient != null && previousClient != channel) {
        try {
          previousClient.sink.close();
        } catch (_) {}
      }
      onDiagnostic?.call('🔗 [Browser STT] WebView connected');

      channel.stream.listen(
        (message) {
          if (!_isActive || _wsClient != channel) return;
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
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
                      '🎤 [Browser STT] Web Speech API active — speak now');
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
                    '🎙️ [Browser STT] Input ready: $_selectedAudioInputDeviceLabel');
                break;
              case 'watchdogRestart':
                final reason = data['reason'] as String? ?? 'stale';
                final ageMs = (data['ageMs'] as num?)?.toInt() ?? 0;
                onDiagnostic?.call(
                    '[Browser STT] Restarting recognizer after ${ageMs ~/ 1000}s without speech events ($reason)');
                break;
              case 'error':
                final err = data['error'] as String? ?? 'unknown';
                if (err == 'input-device-missing') {
                  onDiagnostic?.call(
                      '⚠️ [Browser STT] Selected microphone unavailable; using system default.');
                } else if (err == 'input-device-failed') {
                  onDiagnostic?.call(
                      '⚠️ [Browser STT] Could not open selected microphone; using system default.');
                } else if (err == 'not-allowed') {
                  onError?.call('Microphone blocked in WebView2.\n'
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
          final wasCurrentClient = _wsClient == channel;
          if (wasCurrentClient) {
            _wsClient = null;
          }
          if (_isActive && wasCurrentClient) {
            onDiagnostic?.call('⚠️ [Browser STT] WebView disconnected');
          }
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

    onDiagnostic?.call(
        '🌐 [Browser STT] WebView ready at http://localhost:$_port/?session=$_sessionId');

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
    onDiagnostic?.call('🔤 [Browser STT] Switching locale → $normalized');
    try {
      _wsClient?.sink
          .add(jsonEncode({'type': 'setLocale', 'locale': normalized}));
    } catch (_) {}
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
        ? '🎙️ [Browser STT] Using system default microphone'
        : '🎙️ [Browser STT] Requested microphone: $_selectedAudioInputDeviceLabel');
    try {
      _wsClient?.sink.add(jsonEncode({
        'type': 'setAudioInputDevice',
        'deviceId': normalized ?? '',
        'label': _selectedAudioInputDeviceLabel,
      }));
    } catch (_) {}
  }

  @override
  Future<List<SttAudioInputDevice>> refreshAudioInputDevices() async {
    try {
      _wsClient?.sink.add(jsonEncode({'type': 'refreshAudioInputDevices'}));
    } catch (_) {}
    return _audioInputDevices;
  }

  Future<void> _stopServer() async {
    final client = _wsClient;
    _wsClient = null;
    try {
      client?.sink.close();
    } catch (_) {}
    try {
      await _server?.close(force: true);
    } catch (_) {}
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
  String? get sttWebViewUrl =>
      _server != null ? 'http://localhost:$_port/?session=$_sessionId' : null;

  String _buildHtml(String locale, String? selectedDeviceId) {
    final localeJson = jsonEncode(locale);
    final selectedDeviceJson = jsonEncode(selectedDeviceId ?? '');
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AutoTeleprompter — Pro Audio Console</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0A0A0A;color:#FFBF00;font-family:'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
       display:flex;flex-direction:column;align-items:center;justify-content:center;
       height:100vh;gap:8px;padding:12px;overflow:hidden;border:1px solid #222}
  .header{display:flex;align-items:center;gap:10px;width:100%;justify-content:center}
  .label{font-size:10px;text-transform:uppercase;letter-spacing:1px;color:#555;font-weight:bold}
  #status{font-size:11px;color:#FFBF00;opacity:0.8}
  .visualizer-container{width:100%;height:40px;background:#111;border-radius:6px;overflow:hidden;position:relative;border:1px solid #1a1a1a}
  #waveCanvas{width:100%;height:100%}
  #words{font-size:14px;color:#FFF;text-align:center;width:100%;height:32px;overflow:hidden;display:flex;align-items:center;justify-content:center;font-weight:500;text-shadow:0 0 10px rgba(255,191,0,0.2)}
  #err{color:#FF4444;font-size:10px;text-align:center;width:100%}
  .mic-indicator{width:8px;height:8px;border-radius:50%;background:#333}
  .mic-indicator.on{background:#FFBF00;box-shadow:0 0 8px #FFBF00;animation:pulse 1.5s infinite}
  @keyframes pulse{0%{opacity:1}50%{opacity:.3}100%{opacity:1}}
</style>
</head>
<body>
<div class="header">
  <div class="mic-indicator" id="dot"></div>
  <span class="label">Audio Console</span>
  <div id="status">Connecting...</div>
</div>
<div class="visualizer-container">
  <canvas id="waveCanvas"></canvas>
</div>
<div id="words">Ready for speech</div>
<div id="err"></div>
<script>
const ws = new WebSocket('ws://localhost:$_port/ws');
const dot = document.getElementById('dot');
const status = document.getElementById('status');
const words = document.getElementById('words');
const err = document.getElementById('err');
const canvas = document.getElementById('waveCanvas');
const ctx = canvas.getContext('2d');
let rec;
let currentLocale = $localeJson;
let selectedDeviceId = $selectedDeviceJson;
let consecutiveFails = 0;
let audioContext;
let analyser;
let dataArray;
let activeStream;
let animationId;
let restartTimer;
let watchdogTimer;
let lastError = '';
let lastStartAt = 0;
let lastResultAt = 0;
let lastSpeechEventAt = 0;
let lastHeartbeatAt = 0;
let lastStaleRestartAt = 0;
let switchingLocale = false;
let switchingInput = false;
let closedByHost = false;

function audioConstraints() {
  if (selectedDeviceId) {
    return { audio: { deviceId: { exact: selectedDeviceId } } };
  }
  return { audio: true };
}

async function refreshDevices() {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const inputs = devices
      .filter(d => d.kind === 'audioinput')
      .map((d, index) => ({
        id: d.deviceId,
        label: d.label || ('Microphone ' + (index + 1))
      }));
    send({type: 'devices', devices: inputs});
    return inputs;
  } catch(e) {
    return [];
  }
}

function stopActiveStream() {
  if (!activeStream) return;
  activeStream.getTracks().forEach(track => track.stop());
  activeStream = null;
}

async function initVisualizer() {
  try {
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }
    stopActiveStream();
    analyser = audioContext.createAnalyser();
    analyser.fftSize = 256;
    const bufferLength = analyser.frequencyBinCount;
    dataArray = new Uint8Array(bufferLength);

    try {
      activeStream = await navigator.mediaDevices.getUserMedia(audioConstraints());
    } catch(e) {
      if (selectedDeviceId) {
        selectedDeviceId = '';
        send({type: 'error', error: e.name === 'OverconstrainedError' ? 'input-device-missing' : 'input-device-failed'});
        activeStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } else {
        throw e;
      }
    }

    const source = audioContext.createMediaStreamSource(activeStream);
    source.connect(analyser);
    await refreshDevices();
    const currentTrack = activeStream.getAudioTracks()[0];
    const trackLabel = currentTrack ? currentTrack.label : '';
    if (trackLabel) send({type: 'inputReady', label: trackLabel});
    if (!animationId) draw();
  } catch (e) {
    console.error('Visualizer mic error:', e);
    send({type: 'error', error: e.name === 'NotAllowedError' ? 'not-allowed' : 'input-device-failed'});
  }
}

function draw() {
  animationId = requestAnimationFrame(draw);
  analyser.getByteFrequencyData(dataArray);
  
  const width = canvas.width;
  const height = canvas.height;
  ctx.clearRect(0, 0, width, height);
  
  const barWidth = (width / dataArray.length) * 2.5;
  let x = 0;
  let sum = 0;
  
  for(let i = 0; i < dataArray.length; i++) {
    const barHeight = (dataArray[i] / 255) * height;
    ctx.fillStyle = i % 2 === 0 ? '#FFBF00' : '#886600';
    ctx.fillRect(x, height - barHeight, barWidth, barHeight);
    x += barWidth + 1;
    sum += dataArray[i];
  }
  
  // Calculate average volume (0.0 to 1.0) and send to Flutter
  const avgVol = sum / dataArray.length / 255.0;
  // Boost the signal slightly so even quiet speech registers
  const normalizedVol = Math.min(1.0, avgVol * 2.5);
  // Send every ~300ms to avoid flooding the websocket
  if (!window.lastVolSend || Date.now() - window.lastVolSend > 300) {
     send({type: 'level', level: normalizedVol});
     window.lastVolSend = Date.now();
  }
}

ws.onopen = async () => {
  status.textContent = 'Mic Start...';
  await initVisualizer();
  ensureWatchdog();
  startRec(currentLocale);
};
ws.onclose = () => {
  closedByHost = true;
  if(restartTimer) clearTimeout(restartTimer);
  if(watchdogTimer) clearInterval(watchdogTimer);
  status.textContent = 'Standby';
  dot.classList.remove('on');
  if(rec) rec.abort();
  stopActiveStream();
};
ws.onmessage = (e) => {
  const d = JSON.parse(e.data);
  if(d.type === 'setLocale' && d.locale !== currentLocale) {
    currentLocale = d.locale; consecutiveFails = 0; switchingLocale = true;
    status.textContent = 'Syncing ' + d.locale;
    if(restartTimer) clearTimeout(restartTimer);
    if(rec) rec.abort();
    scheduleRestart(80, 'locale-switch');
  }
  if(d.type === 'setAudioInputDevice') {
    selectedDeviceId = d.deviceId || '';
    switchingInput = true;
    status.textContent = selectedDeviceId ? 'Switching input' : 'System input';
    if(restartTimer) clearTimeout(restartTimer);
    if(rec) rec.abort();
    initVisualizer().finally(() => {
      switchingInput = false;
      if(!closedByHost && ws.readyState === 1) {
        scheduleRestart(250, 'input-switch');
      }
    });
  }
  if(d.type === 'refreshAudioInputDevices') {
    refreshDevices();
  }
};

function send(o){if(ws.readyState===1)ws.send(JSON.stringify(o));}

function scheduleRestart(delay, reason) {
  if(closedByHost || ws.readyState !== 1) return;
  if(switchingLocale && reason !== 'locale-switch') return;
  if(switchingInput && reason !== 'input-switch') return;
  if(restartTimer) clearTimeout(restartTimer);
  status.textContent = 'Restarting';
  restartTimer = setTimeout(() => startRec(currentLocale), delay);
}

function restartDelay() {
  if(lastError === 'no-speech') return 120;
  if(lastError === 'network') return Math.min(900 + consecutiveFails * 350, 2600);
  if(consecutiveFails <= 2) return 240;
  return Math.min(300 * Math.pow(2, consecutiveFails - 2), 3000);
}

function ensureWatchdog() {
  if(watchdogTimer) return;
  watchdogTimer = setInterval(() => {
    if(closedByHost || ws.readyState !== 1 || switchingLocale || switchingInput) return;
    if(restartTimer) return;
    const dotOn = dot.classList.contains('on');
    const now = Date.now();
    if(now - lastHeartbeatAt > 5000) {
      lastHeartbeatAt = now;
      send({
        type: 'heartbeat',
        listening: dotOn,
        locale: currentLocale,
        ageMs: lastSpeechEventAt > 0 ? now - lastSpeechEventAt : 0,
        failures: consecutiveFails
      });
    }
    if(!rec) {
      scheduleRestart(120, 'watchdog-missing-rec');
      return;
    }
    if(!dotOn && lastStartAt > 0 && now - lastStartAt > 1800) {
      scheduleRestart(120, 'watchdog-idle');
      return;
    }
    if(dotOn && lastSpeechEventAt > 0 && now - lastSpeechEventAt > 25000 &&
       now - lastStaleRestartAt > 30000) {
      lastStaleRestartAt = now;
      send({type: 'watchdogRestart', reason: 'stale-speech-events', ageMs: now - lastSpeechEventAt});
      try { rec.abort(); } catch(e) {}
      scheduleRestart(250, 'watchdog-stale');
    }
  }, 1000);
}

function startRec(locale) {
  if(closedByHost || ws.readyState !== 1) return;
  if(restartTimer) { clearTimeout(restartTimer); restartTimer = null; }
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if(!SR){ err.textContent = 'Browser STT Unavailable'; return; }
  rec = new SR();
  rec.lang = locale; rec.continuous = true; rec.interimResults = true;
  rec.onstart = () => {
    switchingLocale = false; consecutiveFails = 0; lastError = ''; lastStartAt = Date.now(); lastSpeechEventAt = lastStartAt; dot.classList.add('on');
    status.textContent = '[' + locale.toUpperCase() + '] Active'; 
    // ALWAYS send listening to clear the UI's 'starting' state
    send({type: 'listening'});
    if (audioContext && audioContext.state === 'suspended') audioContext.resume();
  };
  rec.onresult = (e) => {
    consecutiveFails = 0; lastError = ''; lastResultAt = Date.now(); lastSpeechEventAt = lastResultAt;
    for(let i = e.resultIndex; i < e.results.length; i++){
      const t = e.results[i][0].transcript;
      const f = e.results[i].isFinal;
      send({type: 'result', words: t, isFinal: f});
      send({type: 'level', level: 0.65});
      words.textContent = t.length > 30 ? '...' + t.slice(-30) : t;
    }
  };
  rec.onaudiostart = () => { lastSpeechEventAt = Date.now(); };
  rec.onsoundstart = () => { lastSpeechEventAt = Date.now(); };
  rec.onspeechstart = () => { lastSpeechEventAt = Date.now(); send({type: 'level', level: 0.7}); };
  rec.onspeechend = () => { lastSpeechEventAt = Date.now(); send({type: 'level', level: 0.1}); };
  rec.onerror = (e) => {
    if(e.error === 'aborted') return;
    lastSpeechEventAt = Date.now();
    lastError = e.error || '';
    send({type: 'error', error: e.error});
    if(e.error === 'not-allowed') {
      err.textContent = 'Mic Permission Denied';
      dot.classList.remove('on');
    }
    if(e.error !== 'no-speech') {
      consecutiveFails++;
    } else {
      consecutiveFails = 0;
    }
  };
  rec.onend = () => {
    dot.classList.remove('on');
    if(closedByHost || ws.readyState !== 1) return;
    if(switchingLocale) return;
    if(switchingInput) return;
    scheduleRestart(restartDelay(), 'recognition-ended');
  };
  try{ rec.start(); } catch(ex){
    lastError = 'start-failed'; consecutiveFails++;
    if(!closedByHost && ws.readyState === 1) {
      scheduleRestart(restartDelay(), 'start-failed');
    }
  }
}

// Canvas resizing
function resize() { canvas.width = canvas.clientWidth; canvas.height = canvas.clientHeight; }
window.onresize = resize;
resize();
</script>
</body>
</html>
''';
  }
}
