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
let rec;
let currentLocale = $localeJson;
let selectedDeviceId = $selectedDeviceJson;
let selectedDeviceLabel = $selectedDeviceLabelJson;
let consecutiveFails = 0;
let consecutiveNetworkFails = 0;
let audioContext;
let analyser;
let timeDataArray;
let activeStream;
let meterTimer;
let restartTimer;
let watchdogTimer;
let lastError = '';
let lastStartAt = 0;
let startRequestedAt = 0;
let lastResultAt = 0;
let lastHeartbeatAt = 0;
let lastLeaseRestartAt = 0;
let meterLevel = 0;
let lastMeterSendAt = 0;
const meterSilenceFloorDb = -60;
const meterCeilingDb = -12;
const meterAttack = 0.45;
const meterRelease = 0.10;
let switchingLocale = false;
let switchingInput = false;
let closedByHost = false;
let recognitionGeneration = 0;
let restartGeneration = 0;
let restartSuppressed = false;
let recognitionInputMode = 'unstarted';

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
    timeDataArray = new Float32Array(analyser.fftSize);
    resetMeter();

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
    startMeterSampling();
    // Device enumeration is informational after the stream is open. Do not
    // hold recognizer startup behind a slow browser/OS device-list refresh.
    refreshDevices();
  } catch (e) {
    console.error('Visualizer mic error:', e);
    resetMeter();
    if(e.name === 'NotAllowedError' || e.name === 'SecurityError') {
      sendLifecycle('permissionDenied');
    } else {
      send({type: 'error', error: 'input-device-failed'});
    }
  }
}

function startMeterSampling() {
  if(meterTimer) return;
  sampleMeter();
  meterTimer = setInterval(sampleMeter, 100);
}

function stopMeterSampling() {
  if(meterTimer) clearInterval(meterTimer);
  meterTimer = null;
}

function sampleMeter() {
  if(!analyser || !timeDataArray) return;
  analyser.getFloatTimeDomainData(timeDataArray);

  let mean = 0;
  for(let i = 0; i < timeDataArray.length; i++) mean += timeDataArray[i];
  mean /= timeDataArray.length;
  let sumSquares = 0;
  for(let i = 0; i < timeDataArray.length; i++) {
    const centered = timeDataArray[i] - mean;
    sumSquares += centered * centered;
  }
  const rms = Math.sqrt(sumSquares / timeDataArray.length);
  const rmsDb = 20 * Math.log10(Math.max(rms, 1e-7));
  const targetLevel = rmsDb <= meterSilenceFloorDb
    ? 0
    : Math.min(
        1,
        Math.max(
          0,
          (rmsDb - meterSilenceFloorDb) /
            (meterCeilingDb - meterSilenceFloorDb)
        )
      );
  const smoothing = targetLevel > meterLevel ? meterAttack : meterRelease;
  meterLevel += (targetLevel - meterLevel) * smoothing;
  if(meterLevel < 0.005) meterLevel = 0;

  // Meter telemetry is presentation-only. Recognition remains exclusively
  // driven by SpeechRecognition.onresult below.
  const now = Date.now();
  if(now - lastMeterSendAt >= 100) {
    send({type: 'level', level: meterLevel});
    lastMeterSendAt = now;
  }
}

function shutdownVisualizer() {
  stopMeterSampling();
  resetMeter();
  stopActiveStream();
  analyser = null;
  timeDataArray = null;
  const closingContext = audioContext;
  audioContext = null;
  if(closingContext) {
    try { closingContext.close().catch(() => {}); } catch(e) {}
  }
}

function resetMeter() {
  meterLevel = 0;
  lastMeterSendAt = 0;
  send({type: 'level', level: 0.0});
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
  shutdownVisualizer();
};
ws.onmessage = (e) => {
  const d = JSON.parse(e.data);
  if(d.type === 'close') {
    closedByHost = true;
    cancelScheduledRestart();
    if(watchdogTimer) clearInterval(watchdogTimer);
    invalidateRecognition();
    shutdownVisualizer();
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

function invalidateRecognition() {
  const recognizer = rec;
  recognitionGeneration++;
  rec = null;
  startRequestedAt = 0;
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

function startRecognitionWithConfiguredInput(recognizer) {
  const track = activeStream && activeStream.getAudioTracks
    ? activeStream.getAudioTracks()[0]
    : null;
  if(selectedDeviceId && track && track.readyState === 'live') {
    try {
      // Chromium 133+ accepts an audio MediaStreamTrack. Reusing the stream
      // already opened for the meter keeps an explicitly selected device on
      // that exact input.
      recognizer.start(track);
      recognitionInputMode = 'selected-stream';
      send({type: 'recognitionInput', mode: recognitionInputMode});
      return;
    } catch(e) {
      // Older or incompatible runtimes reject the overload synchronously.
      // Preserve the original browser-owned microphone path as a fallback.
    }
  }
  // Preserve the original, proven Web Speech path for the system default.
  // Feeding the metering track through start(track) changed cloud recognition
  // behaviour on some Chromium/WebView2 versions and produced tiny fragments.
  recognizer.start();
  recognitionInputMode = 'default-microphone';
  send({type: 'recognitionInput', mode: recognitionInputMode});
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
    if(!dotOn && startRequestedAt > 0 && now - startRequestedAt > 10000) {
      invalidateRecognition();
      scheduleRestart(120, 'watchdog-start-timeout');
      return;
    }
    // Renew a recognizer that claims to stay active forever without using
    // ordinary silence as a failure signal. Normal Chromium onend cycles reset
    // lastStartAt long before this bounded lease expires.
    if(dotOn && lastStartAt > 0 &&
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
  startRequestedAt = Date.now();
  lastStartAt = 0;
  recognizer.lang = locale;
  recognizer.continuous = true;
  recognizer.interimResults = true;
  recognizer.maxAlternatives = 3;
  recognizer.onstart = () => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    startRequestedAt = 0;
    lastError = ''; lastStartAt = Date.now();
    dot.classList.add('on');
    status.textContent = '[' + locale.toUpperCase() + '] Active';
    // Always signal recognizer readiness so the host can leave starting state.
    sendLifecycle('recognizerListening');
    if (audioContext && audioContext.state === 'suspended') audioContext.resume();
  };
  recognizer.onresult = (e) => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    const snapshotParts = [];
    let snapshotIsFinal = true;
    for(let i = 0; i < e.results.length; i++){
      const t = e.results[i][0].transcript;
      if(typeof t !== 'string' || t.trim().length === 0) continue;
      snapshotParts.push(t.trim());
      if(!e.results[i].isFinal) snapshotIsFinal = false;
    }
    const snapshotTranscript = snapshotParts.join(' ').trim();
    if(snapshotTranscript.length > 0) {
      const alternatives = [];
      for(let i = e.resultIndex; i < e.results.length; i++){
        const result = e.results[i];
        for(let alternativeIndex = 1;
            alternativeIndex < result.length && alternatives.length < 4;
            alternativeIndex++) {
          const alternative = result[alternativeIndex].transcript;
          if(typeof alternative !== 'string' || alternative.trim().length === 0) {
            continue;
          }
          const candidateParts = [];
          for(let snapshotIndex = 0;
              snapshotIndex < e.results.length;
              snapshotIndex++) {
            const candidate = snapshotIndex === i
              ? alternative
              : e.results[snapshotIndex][0].transcript;
            if(typeof candidate === 'string' && candidate.trim().length > 0) {
              candidateParts.push(candidate.trim());
            }
          }
          const candidateTranscript = candidateParts.join(' ').trim();
          if(candidateTranscript.length > 0 &&
             candidateTranscript !== snapshotTranscript &&
             !alternatives.includes(candidateTranscript)) {
            alternatives.push(candidateTranscript);
          }
        }
      }
      send({
        type: 'result',
        words: snapshotTranscript,
        isFinal: snapshotIsFinal,
        isCumulative: true,
        streamId: generation,
        alternatives: alternatives
      });
      words.textContent = snapshotTranscript.length > 30
        ? '...' + snapshotTranscript.slice(-30)
        : snapshotTranscript;
      consecutiveFails = 0;
      consecutiveNetworkFails = 0;
      lastError = '';
      lastResultAt = Date.now();
    }
  };
  recognizer.onerror = (e) => {
    if(!isCurrentRecognition(recognizer, generation)) return;
    if(e.error === 'aborted') return;
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
    startRequestedAt = 0;
    dot.classList.remove('on');
    if(closedByHost || ws.readyState !== 1) return;
    if(restartSuppressed) return;
    if(switchingLocale) return;
    if(switchingInput) return;
    scheduleRestart(restartDelay(), 'recognition-ended');
  };
  try{ startRecognitionWithConfiguredInput(recognizer); } catch(ex){
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

</script>
</body>
</html>
''';
  }
}
