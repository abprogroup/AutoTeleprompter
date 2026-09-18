part of 'stt_browser_adapter.dart';

extension SttBrowserAdapterPage on SttBrowserAdapter {
  String _buildHtml(
    String locale,
    String? selectedDeviceId,
    String selectedDeviceLabel,
  ) {
    final localeJson = jsonEncode(locale);
    final selectedDeviceJson = jsonEncode(selectedDeviceId ?? '');
    final selectedDeviceLabelJson = jsonEncode(selectedDeviceLabel);
    final sessionTokenJson = jsonEncode(_sessionToken);
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AutoTeleprompter - Pro Audio Console</title>
<style nonce="$_sessionToken">
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
<script nonce="$_sessionToken">
const sessionToken = $sessionTokenJson;
const ws = new WebSocket(
  'ws://localhost:$_port/ws?session=' + encodeURIComponent(sessionToken)
);
const dot = document.getElementById('dot');
const status = document.getElementById('status');
const words = document.getElementById('words');
const err = document.getElementById('err');
const canvas = document.getElementById('waveCanvas');
const ctx = canvas.getContext('2d');
let rec;
let currentLocale = $localeJson;
let selectedDeviceId = $selectedDeviceJson;
let selectedDeviceLabel = $selectedDeviceLabelJson;
let consecutiveFails = 0;
let consecutiveNetworkFails = 0;
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
let lastHeartbeatAt = 0;
let lastLeaseRestartAt = 0;
let speechActive = false;
let speechActiveStartedAt = 0;
let speechEvidenceUntil = 0;
let switchingLocale = false;
let switchingInput = false;
let closedByHost = false;
let recognitionGeneration = 0;
let restartGeneration = 0;
let restartSuppressed = false;

function audioConstraints(deviceId) {
  if (deviceId) {
    return { audio: { deviceId: { exact: deviceId } } };
  }
  return { audio: true };
}

function normalizeAudioInputLabel(value) {
  if (typeof value !== 'string') return '';
  return value
    .normalize('NFKC')
    .toLocaleLowerCase()
    .replace(/\\s+/g, ' ')
    .trim();
}

function isSystemDefaultInputLabel(value) {
  const normalized = normalizeAudioInputLabel(value);
  return !normalized ||
    normalized === 'system default microphone' ||
    normalized === 'default' ||
    normalized === 'communications';
}

function findConfiguredAudioInput(inputs) {
  if (selectedDeviceId) {
    const idMatch = inputs.find(d => d.id === selectedDeviceId);
    if (idMatch) return idMatch;
  }

  const wanted = normalizeAudioInputLabel(selectedDeviceLabel);
  if (isSystemDefaultInputLabel(wanted)) return null;

  const exactMatches = inputs.filter(
    d => normalizeAudioInputLabel(d.label) === wanted
  );
  if (exactMatches.length === 1) return exactMatches[0];

  // Browser profiles intentionally use different device IDs. Permit a label
  // containment match only when it is unique and long enough to avoid picking
  // a generic "Microphone" entry.
  const partialMatches = inputs.filter(d => {
    const candidate = normalizeAudioInputLabel(d.label);
    return candidate.length >= 8 && wanted.length >= 8 &&
      (candidate.includes(wanted) || wanted.includes(candidate));
  });
  return partialMatches.length === 1 ? partialMatches[0] : null;
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

function stopStream(stream) {
  if (!stream) return;
  stream.getTracks().forEach(track => track.stop());
}

async function acquireConfiguredAudioStream() {
  if (!selectedDeviceId && isSystemDefaultInputLabel(selectedDeviceLabel)) {
    return navigator.mediaDevices.getUserMedia({ audio: true });
  }

  let directOpenError;
  if (selectedDeviceId) {
    try {
      return await navigator.mediaDevices.getUserMedia(
        audioConstraints(selectedDeviceId)
      );
    } catch(e) {
      if(e.name === 'NotAllowedError' || e.name === 'SecurityError') throw e;
      directOpenError = e;
    }
  }

  // A generic stream grants this browser profile access to device labels.
  // That lets Edge/Chrome remap the WebView2 selection without trusting a
  // profile-specific device ID.
  const fallbackStream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const inputs = await refreshDevices();
  const remapped = findConfiguredAudioInput(inputs);
  if (remapped && remapped.id) {
    try {
      const remappedStream = await navigator.mediaDevices.getUserMedia(
        audioConstraints(remapped.id)
      );
      stopStream(fallbackStream);
      selectedDeviceId = remapped.id;
      return remappedStream;
    } catch(e) {
      send({type: 'error', error: 'input-device-failed'});
      selectedDeviceId = '';
      return fallbackStream;
    }
  }

  send({
    type: 'error',
    error: directOpenError && directOpenError.name === 'OverconstrainedError'
      ? 'input-device-missing'
      : 'input-device-failed'
  });
  selectedDeviceId = '';
  return fallbackStream;
}

function stopActiveStream() {
  if (!activeStream) return;
  stopStream(activeStream);
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

    activeStream = await acquireConfiguredAudioStream();

    const source = audioContext.createMediaStreamSource(activeStream);
    source.connect(analyser);
    if (audioContext.state !== 'running') {
      try { await audioContext.resume(); } catch(e) {}
    }
    if (audioContext.state !== 'running') {
      send({type: 'meterUnavailable'});
    }
    const currentTrack = activeStream.getAudioTracks()[0];
    const trackLabel = currentTrack ? currentTrack.label : '';
    sendLifecycle('microphoneReady');
    if (trackLabel) send({type: 'inputReady', label: trackLabel});
    await refreshDevices();
    if (!animationId) draw();
  } catch (e) {
    console.error('Visualizer mic error:', e);
    if(e.name === 'NotAllowedError' || e.name === 'SecurityError') {
      sendLifecycle('permissionDenied');
    } else {
      send({type: 'error', error: 'input-device-failed'});
    }
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
  // Metering is independent from recognition evidence: users must be able to
  // verify their selected microphone even before Chromium detects speech.
  if (!window.lastVolSend || Date.now() - window.lastVolSend > 100) {
     send({type: 'level', level: normalizedVol});
     window.lastVolSend = Date.now();
  }
}

ws.onopen = async () => {
  sendLifecycle('socketConnected');
  status.textContent = 'Mic Start...';
  await initVisualizer();
  ensureWatchdog();
  startRec(currentLocale);
};
ws.onclose = () => {
  closedByHost = true;
  cancelScheduledRestart();
  if(watchdogTimer) clearInterval(watchdogTimer);
  status.textContent = 'Standby';
  invalidateRecognition();
  stopActiveStream();
};
ws.onmessage = (e) => {
  const d = JSON.parse(e.data);
  if(d.type === 'close') {
    closedByHost = true;
    cancelScheduledRestart();
    if(watchdogTimer) clearInterval(watchdogTimer);
    invalidateRecognition();
    stopActiveStream();
    status.textContent = 'Closed';
    send({type: 'closeAck'});
    setTimeout(() => {
      ws.close();
      window.close();
    }, 0);
    return;
  }
  if(d.type === 'setLocale' && d.locale !== currentLocale) {
    currentLocale = d.locale; consecutiveFails = 0; switchingLocale = true;
    restartSuppressed = false; lastError = '';
    status.textContent = 'Syncing ' + d.locale;
    cancelScheduledRestart();
    invalidateRecognition();
    scheduleRestart(80, 'locale-switch');
  }
  if(d.type === 'setAudioInputDevice') {
    selectedDeviceId = d.deviceId || '';
    selectedDeviceLabel = d.label || 'System default microphone';
    switchingInput = true;
    consecutiveFails = 0; restartSuppressed = false; lastError = '';
    status.textContent =
      selectedDeviceId || !isSystemDefaultInputLabel(selectedDeviceLabel)
        ? 'Switching input'
        : 'System input';
    cancelScheduledRestart();
    invalidateRecognition();
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
function sendLifecycle(phase){send({type: 'lifecycle', phase: phase});}

function isCurrentRecognition(recognizer, generation) {
  return rec === recognizer && recognitionGeneration === generation;
}

function cancelScheduledRestart() {
  restartGeneration++;
  if(restartTimer) clearTimeout(restartTimer);
  restartTimer = null;
}

function resetSpeechEvidence() {
  speechActive = false;
  speechActiveStartedAt = 0;
  speechEvidenceUntil = 0;
  send({type: 'speechReset'});
  send({type: 'level', level: 0.0});
}

function invalidateRecognition() {
  const recognizer = rec;
  recognitionGeneration++;
  rec = null;
  resetSpeechEvidence();
  dot.classList.remove('on');
  if(recognizer) {
    try { recognizer.abort(); } catch(e) {}
  }
}

function isTerminalRecognitionError(errorCode) {
  return errorCode === 'not-allowed' ||
    errorCode === 'service-not-allowed' ||
    errorCode === 'language-not-supported' ||
    errorCode === 'audio-capture' ||
    errorCode === 'bad-grammar';
}

function noteSpeechEvidence() {
  speechEvidenceUntil = Math.max(speechEvidenceUntil, performance.now() + 4000);
}

function endSpeechActivity() {
  const wasActive = speechActive;
  speechActive = false;
  speechActiveStartedAt = 0;
  if(wasActive) {
    speechEvidenceUntil = Math.max(
      speechEvidenceUntil,
      performance.now() + 4000
    );
    send({type: 'speechEnd'});
    send({type: 'level', level: 0.0});
  }
}

function scheduleRestart(delay, reason) {
  if(closedByHost || restartSuppressed || ws.readyState !== 1) return;
  if(switchingLocale && reason !== 'locale-switch') return;
  if(switchingInput && reason !== 'input-switch') return;
  cancelScheduledRestart();
  const scheduledGeneration = restartGeneration;
  status.textContent = 'Restarting';
  restartTimer = setTimeout(() => {
    if(scheduledGeneration !== restartGeneration) return;
    restartTimer = null;
    startRec(currentLocale);
  }, delay);
}

function restartDelay() {
  if(lastError === 'no-speech') return 120;
  if(lastError === 'network') return Math.min(900 + consecutiveFails * 350, 2600);
  if(consecutiveFails <= 2) return 240;
  return Math.min(300 * Math.pow(2, consecutiveFails - 2), 3000);
}

function startRecognitionWithSelectedInput(recognizer) {
  const track = activeStream && activeStream.getAudioTracks
    ? activeStream.getAudioTracks()[0]
    : null;
  if(track && track.readyState === 'live') {
    try {
      // Chromium 133+ can recognize the same MediaStreamTrack used by the
      // meter. Older runtimes throw synchronously and safely fall back below.
      recognizer.start(track);
      return;
    } catch(e) {}
  }
  recognizer.start();
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
        ageMs: lastResultAt > 0 ? now - lastResultAt : 0,
        failures: consecutiveNetworkFails
      });
    }
    if(restartSuppressed) return;
    if(!rec) {
      scheduleRestart(120, 'watchdog-missing-rec');
      return;
    }
    if(!dotOn && lastStartAt > 0 && now - lastStartAt > 1800) {
      invalidateRecognition();
      scheduleRestart(120, 'watchdog-idle');
      return;
    }
    if(speechActive && speechActiveStartedAt > 0 &&
       now - speechActiveStartedAt > 120000) {
      endSpeechActivity();
    }
    // Renew a recognizer that claims to stay active forever without using
    // ordinary silence as a failure signal. Normal Chromium onend cycles reset
    // lastStartAt long before this bounded lease expires.
    if(dotOn && !speechActive && lastStartAt > 0 &&
       now - lastStartAt > 900000 && now - lastLeaseRestartAt > 900000) {
      lastLeaseRestartAt = now;
      send({
        type: 'watchdogRestart',
        reason: 'recognizer-lease-renewal',
        ageMs: now - lastStartAt,
        failures: consecutiveNetworkFails
      });
      invalidateRecognition();
      scheduleRestart(250, 'watchdog-lease-renewal');
    }
  }, 1000);
}

function startRec(locale) {
  if(closedByHost || restartSuppressed || ws.readyState !== 1) return;
  if(restartTimer) cancelScheduledRestart();
  if(rec) invalidateRecognition();
  switchingLocale = false;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if(!SR){
    restartSuppressed = true;
    err.textContent = 'Browser speech-to-text unavailable';
    sendLifecycle('speechApiUnavailable');
    return;
  }
  const recognizer = new SR();
  const generation = ++recognitionGeneration;
  rec = recognizer;
  lastStartAt = Date.now();
  recognizer.lang = locale;
  recognizer.continuous = true;
  recognizer.interimResults = true;
  recognizer.onstart = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    lastError = ''; lastStartAt = Date.now(); resetSpeechEvidence();
    dot.classList.add('on');
    status.textContent = '[' + locale.toUpperCase() + '] Active';
    // Always signal recognizer readiness so the host can leave starting state.
    sendLifecycle('recognizerListening');
    if (audioContext && audioContext.state === 'suspended') audioContext.resume();
  };
  recognizer.onresult = (e) => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    const evidenceNow = performance.now();
    if(!speechActive && evidenceNow > speechEvidenceUntil) return;
    let acceptedResult = false;
    for(let i = e.resultIndex; i < e.results.length; i++){
      const t = e.results[i][0].transcript;
      if(typeof t !== 'string' || t.trim().length === 0) continue;
      const f = e.results[i].isFinal;
      send({type: 'result', words: t, isFinal: f});
      words.textContent = t.length > 30 ? '...' + t.slice(-30) : t;
      acceptedResult = true;
    }
    if(acceptedResult) {
      consecutiveFails = 0;
      consecutiveNetworkFails = 0;
      lastError = '';
      lastResultAt = Date.now();
    }
  };
  recognizer.onspeechstart = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    speechActive = true;
    speechActiveStartedAt = Date.now();
    noteSpeechEvidence();
    send({type: 'speechStart'});
  };
  recognizer.onspeechend = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    endSpeechActivity();
  };
  recognizer.onsoundend = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    endSpeechActivity();
  };
  recognizer.onaudioend = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    endSpeechActivity();
  };
  recognizer.onerror = (e) => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    if(e.error === 'aborted') return;
    resetSpeechEvidence();
    lastError = e.error || '';
    if(isTerminalRecognitionError(lastError)) restartSuppressed = true;
    if(e.error === 'network') {
      consecutiveFails++;
      consecutiveNetworkFails++;
      sendLifecycle('network');
    } else if(e.error === 'not-allowed' || e.error === 'service-not-allowed') {
      consecutiveFails++;
      sendLifecycle('permissionDenied');
    } else {
      if(e.error === 'no-speech') {
        consecutiveFails = 0;
      } else {
        consecutiveFails++;
      }
      send({type: 'error', error: e.error});
    }
    if(restartSuppressed) {
      err.textContent =
        e.error === 'not-allowed' || e.error === 'service-not-allowed'
          ? 'Mic Permission Denied'
          : 'Speech recognition unavailable';
      dot.classList.remove('on');
    }
  };
  recognizer.onend = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    recognitionGeneration++;
    rec = null;
    resetSpeechEvidence();
    dot.classList.remove('on');
    if(closedByHost || ws.readyState !== 1) return;
    if(restartSuppressed) return;
    if(switchingLocale) return;
    if(switchingInput) return;
    scheduleRestart(restartDelay(), 'recognition-ended');
  };
  try{ startRecognitionWithSelectedInput(rec); } catch(ex){
    if(!isCurrentRecognition(recognizer, generation)) return;
    const errorName = ex && typeof ex.name === 'string' ? ex.name : '';
    if(errorName === 'NotAllowedError' || errorName === 'SecurityError') {
      lastError = 'not-allowed';
      restartSuppressed = true;
      sendLifecycle('permissionDenied');
    } else if(errorName === 'NotSupportedError') {
      lastError = 'speech-api-unavailable';
      restartSuppressed = true;
      sendLifecycle('speechApiUnavailable');
    } else {
      lastError = 'start-failed';
      consecutiveFails++;
    }
    invalidateRecognition();
    if(!closedByHost && !restartSuppressed && ws.readyState === 1) {
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
