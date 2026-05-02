---
name: Remote MVP
type: component
platform: Windows
last_updated: 2026-04-27
---

# Remote MVP - Windows

Governs the dormant local remote-control service for Windows. It serves a simple
local HTTP page and WebSocket command stream so external devices can send
teleprompter commands over the local network when premium remote features are
restored.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/remote/services/remote_control_service.dart` | `RemoteControlService`, port 8080 HTTP server, `/` page, `/ws` WebSocket, `onCommand` stream, `remoteControlProvider` |
| `Platform_Windows/lib/features/teleprompter/providers/teleprompter_provider.dart` | `_remoteControlService` lifecycle and `_setupRemoteCallbacks()` placeholder only |

---

## External API

| Method / Field | Caller |
|----------------|--------|
| `remoteControlProvider` | `TeleprompterNotifier.build()` |
| `RemoteControlService.start()` | Future restored remote UI or lifecycle code |
| `RemoteControlService.stop()` | `TeleprompterNotifier.ref.onDispose()` and future lifecycle code |
| `RemoteControlService.onCommand` | Future `_setupRemoteCallbacks()` subscription |
| HTTP `GET /` | Browser/phone remote page |
| WebSocket `GET /ws` | Browser/phone command channel |

---

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Provider construction | `teleprompter_provider.dart` | `ref.read(remoteControlProvider)` |
| Provider disposal | `teleprompter_provider.dart` | Calls `_remoteControlService.stop()` |
| Remote callback hook | `teleprompter_provider.dart` | `_setupRemoteCallbacks()` currently empty because remote is hidden |
| Future remote dashboard | `script_gallery_screen.dart` when restored | Expected to call `start()`, `stop()`, display server status |
| Remote web client | HTML served by `remote_control_service.dart` | Sends WebSocket messages like `TOGGLE`, `FASTER`, `SLOWER`, `RESET`, `MODE_MANUAL`, `MODE_AUTO` |

---

## Endpoint Schemas

The earlier Windows MVP documented endpoint behavior; the current code exposes
these active routes:

| Endpoint | Protocol | Payload | Purpose |
|----------|----------|---------|---------|
| `/` | HTTP GET | HTML string | Renders standard remote console |
| `/ws` | WebSocket GET | Raw command string | Streams `MODE_MANUAL`, `MODE_AUTO`, `TOGGLE`, `FASTER`, `SLOWER`, and `RESET` commands |

Historical note: an older MVP note mentioned HTTP `POST /api/command` with JSON
`{"cmd": "SPEED_UP"}`. That route is not registered in the current Windows
service and must not be treated as active unless code is restored deliberately.

---

## Invariants

1. **Port 8080 is the Remote port**: `RemoteControlService` binds
   `InternetAddress.anyIPv4` on port `8080`. Do not reuse this port for Windows
   STT browser fallback, which uses a separate STT port.

2. **STT browser fallback is separate**: `stt_browser_adapter.dart` owns port
   `8082`. Remote code must not depend on or mutate STT WebView state.

3. **Command stream is string-only**: `onCommand` emits raw command strings from
   WebSocket messages. Teleprompter code translates commands; the remote service
   does not own scroll state.

4. **Remote is currently hidden**: `_setupRemoteCallbacks()` is intentionally
   empty for the stable core build. Restoring remote controls is a V5/premium
   feature and must be explicit.

5. **Server cleanup is mandatory**: `stop()` must close `_server` and null it so
   the port can be rebound in later sessions.

6. **Broadcast stream stays broadcast**: `_onCommand` is a broadcast stream so
   restored dashboards and provider listeners can coexist.

---

## Forbidden Changes

- Do not bind another Windows service to port `8080`.
- Do not move teleprompter scroll-speed state into `RemoteControlService`.
- Do not auto-start the remote server in stable/core builds unless the user
  explicitly restores remote features.
- Do not merge Remote and STT browser WebSocket servers.
- Do not run remote command mutations from multiple isolates without a single
  command coordinator.

---

## Known Fragilities

- **Port collision**: Port `8080` may already be used by developer tooling. The
  current service does not implement dynamic fallback.
- **Hidden code drift**: Remote is dormant, so API drift can happen silently if
  provider callbacks are restored without reading this doc.
- **LAN exposure**: Binding to `anyIPv4` exposes the page on the local network.
  Do not add privileged actions without authentication or local-only controls.

---

## Shared-File Ownership Notes

Remote owns only `_remoteControlService`, `_setupRemoteCallbacks()`, and remote
lifecycle calls inside `teleprompter_provider.dart`. STT session logic and word
advancement in the same file belong to STT and Teleprompter Engine MVPs.

---

## Preserved Original Contract Rows

The following rows and notes existed in the prior Windows Remote MVP and remain
preserved so hardening is additive, not destructive. Where current code differs,
the difference is called out above instead of deleting the old protocol row.

Legacy exact title marker: `# Remote MVP â€” Windows`

Prior scope statement: Governs the integration of the embedded hardware remote
controls. It sets up an isolated `shelf` HTTP/WebSocket local daemon on port
8080 so external controllers (or phones) can securely manage the teleprompter
scrolling behavior over a local area network.

| Original Owned File Row | Preserved Role |
|-------------------------|----------------|
| `Platform_Windows/lib/features/remote/services/remote_control_service.dart` | Serves the raw HTML console and parses internal action requests (`MODE_MANUAL`, `MODE_AUTO`, `TOGGLE`, `FASTER`, `SLOWER`, `RESET`) |

| Endpoint | Protocol | Payload | Purpose |
|----------|----------|---------|---------|
| `/` | HTTP GET | HTML string | Renders standard remote console |
| `/api/command` | HTTP POST | JSON `{"cmd": "SPEED_UP"}` | Executes layout changes |

| Original API Row | Preserved Where Called |
|------------------|------------------------|
| `start()` | Global application boot configurations |
| `stop()` | App disposal routines / app lifecycle state changes |
| `onCommand` | Listening stream inside main state adapters |

| Original Caller Row | Preserved What It Calls |
|---------------------|-------------------------|
| Core Broadcaster UI / `teleprompter_provider.dart` | Subscribes to the `onCommand` stream |

1. **Port Binding Locks**: The service actively binds to `InternetAddress.anyIPv4` on port `8080`. Do NOT attempt to bind alternative services to this port.
2. **State Passing Isolation**: The web client interface does NOT track internal speed values--it only pipes commands asynchronously.
2. **State Passing Isolation**: The web client interface does NOT track internal speed valuesâ€”it only pipes commands asynchronously.

- Do not run state updates on multiple background isolates (web-sockets require a single instance path).
- Port 8080 may be occupied by other developer tools, leading to uncaught binding exceptions. Consider adding dynamic fallback configurations in the future.

```markdown
---
name: Remote MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Remote MVP â€” Windows

Governs the integration of the embedded hardware remote controls. It sets up an isolated `shelf` HTTP/WebSocket local daemon on port 8080 so external controllers (or phones) can securely manage the teleprompter scrolling behavior over a local area network.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/remote/services/remote_control_service.dart` | Serves the raw HTML console and parses internal action requests (`MODE_MANUAL`, `MODE_AUTO`, `TOGGLE`, `FASTER`, `SLOWER`, `RESET`) |

## Endpoint Schemas

| Endpoint | Protocol | Payload | Purpose |
|----------|----------|---------|---------|
| `/` | HTTP GET | HTML string | Renders standard remote console |
| `/api/command` | HTTP POST | JSON `{"cmd": "SPEED_UP"}` | Executes layout changes |

---

## External API (what outside code may call)

| Method / Field | Where called |
|----------------|-------------|
| `start()` | Global application boot configurations |
| `stop()` | App disposal routines / app lifecycle state changes |
| `onCommand` | Listening stream inside main state adapters |

---

## All Callers (outside the MVP files)

| Caller | File | What it calls |
|--------|------|---------------|
| Core Broadcaster UI | `teleprompter_provider.dart` | Subscribes to the `onCommand` stream |

---

## Invariants

1. **Port Binding Locks**: The service actively binds to `InternetAddress.anyIPv4` on port `8080`. Do NOT attempt to bind alternative services to this port.

2. **State Passing Isolation**: The web client interface does NOT track internal speed valuesâ€”it only pipes commands asynchronously.

---

## Forbidden Changes

- Do not run state updates on multiple background isolates (web-sockets require a single instance path).

---

## Known Fragilities

- Port 8080 may be occupied by other developer tools, leading to uncaught binding exceptions. Consider adding dynamic fallback configurations in the future.
```
