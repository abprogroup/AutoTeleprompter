part of 'remote_control_service.dart';

const String remoteControlHtml = '''
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
        button:disabled { opacity: 0.38; transform: none; }
        .active { background: #FFBF00 !important; color: black !important; border-color: #FFBF00; }
        .full { grid-column: span 2; padding: 25px 10px; }
        .reset { background: #331A1A; color: #FF4444; border-color: #441A1A; }
        .status { margin-top: 20px; color: #444; font-size: 11px; }
        .pair { max-width: 400px; margin: 0 auto 20px; padding: 15px; background: #111; border-radius: 15px; }
        input { width: 100%; box-sizing: border-box; background: #050505; color: white; border: 1px solid #333; border-radius: 10px; padding: 14px; text-align: center; font-size: 22px; letter-spacing: 8px; margin-bottom: 10px; }
        .hidden { display: none; }
        .speed { max-width: 400px; margin: 0 auto 18px; text-align: left; }
        .speed-row { display: flex; align-items: center; gap: 12px; }
        .speed input { flex: 1; accent-color: #FFBF00; }
        .speed input:disabled { opacity: 0.35; }
        .speed-value { min-width: 76px; color: #FFBF00; font-weight: bold; text-align: right; }
        .speed-lock { color: #777; font-size: 11px; min-height: 16px; margin-top: 4px; text-align: center; }
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
        </div>
        <div class="speed">
            <div class="speed-row">
                <input id="speed" type="range" min="-300" max="300" step="5" value="0" oninput="setSpeed(this.value)">
                <span id="speed_value" class="speed-value">0 wpm</span>
            </div>
            <div id="speed_lock" class="speed-lock"></div>
        </div>
        <div class="grid">
            <button class="full reset" onclick="send('RESET')">RESET POSITION</button>
        </div>
    </div>

    <div class="section">
        <span class="label">Bookmarks</span>
        <div class="grid">
            <button onclick="send('BOOKMARK_PREVIOUS')">PREVIOUS MARK</button>
            <button onclick="send('BOOKMARK_NEXT')">NEXT MARK</button>
            <button onclick="send('BOOKMARK_ADD')">ADD MARK</button>
            <button onclick="send('BOOKMARK_REMOVE')">REMOVE MARK</button>
        </div>
    </div>

    <div class="section">
        <span class="label">Display</span>
        <div class="grid">
            <button class="full" onclick="send('INVERT_COLORS')">INVERT SCRIPT COLORS</button>
        </div>
    </div>
    </div>

    <div id="log" class="status">Connecting...</div>

    <script>
        let ws;
        let token = '';
        let lastState = {
            scriptActive: false,
            scrollMode: 'auto',
            scrollSpeed: 0,
        };
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
            ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    if (data.type === 'STATE') applyState(data);
                } catch (_) {
                    document.getElementById('log').innerText = 'REMOTE STATE ERROR';
                }
            };
        }
        function send(cmd) {
            if (!lastState.scriptActive) return;
            if(ws && ws.readyState === 1) ws.send(cmd);
        }
        function setMode(mode) {
            if (!scriptControlsEnabled()) return;
            send(mode);
            applyState({
                type: 'STATE',
                scriptActive: true,
                scrollMode: mode === 'MODE_MANUAL' ? 'manual' : 'auto',
                scrollSpeed: Number(document.getElementById('speed').value || 0),
            });
        }
        function setSpeed(value) {
            if (!speedControlsEnabled()) return;
            const speed = Math.max(-300, Math.min(300, Number(value) || 0));
            updateSpeedLabel(speed);
            send('SET_SPEED:' + speed.toFixed(0));
        }
        function applyState(data) {
            const scriptActive = data.scriptActive === true;
            const manual = data.scrollMode === 'manual';
            const speed = Math.max(-300, Math.min(300, Number(data.scrollSpeed) || 0));
            lastState = { scriptActive, scrollMode: manual ? 'manual' : 'auto', scrollSpeed: speed };
            document.getElementById('btn_manual').classList.toggle('active', manual);
            document.getElementById('btn_auto').classList.toggle('active', !manual);
            document.querySelectorAll('#controls button').forEach((button) => {
                button.disabled = !scriptActive;
            });
            const slider = document.getElementById('speed');
            slider.disabled = !scriptActive || !manual;
            slider.value = speed;
            updateSpeedLabel(speed);
            document.getElementById('speed_lock').innerText = !scriptActive
                ? 'Open a script in Present mode to enable remote controls'
                : manual
                ? 'Manual speed synced with presenter'
                : 'Speed locked while Speech Follow is active';
        }
        function scriptControlsEnabled() {
            return lastState.scriptActive === true;
        }
        function speedControlsEnabled() {
            const slider = document.getElementById('speed');
            return slider && !slider.disabled;
        }
        function updateSpeedLabel(speed) {
            const sign = speed > 0 ? '+' : '';
            document.getElementById('speed_value').innerText = sign + Math.round(speed) + ' wpm';
        }
    </script>
</body>
</html>
''';
