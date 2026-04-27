---
name: Remote MVP
type: feature
platforms: Windows
last_updated: 2026-04-27
---

# Remote MVP — Windows

Governs the integration of the embedded hardware remote controls. It sets up an isolated `shelf` HTTP/WebSocket local daemon on port 8080 so external controllers (or phones) can securely manage the teleprompter scrolling behavior over a local area network.

---

## Owned Files

| File | Role |
|------|------|
| `Platform_Windows/lib/features/remote/services/remote_control_service.dart` | Serves the raw HTML console and parses internal action requests (`MODE_MANUAL`, `MODE_AUTO`, `TOGGLE`, `FASTER`, `SLOWER`, `RESET`) |

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

2. **State Passing Isolation**: The web client interface does NOT track internal speed values—it only pipes commands asynchronously.

---

## Forbidden Changes

- Do not run state updates on multiple background isolates (web-sockets require a single instance path).

---

## Known Fragilities

- Port 8080 may be occupied by other developer tools, leading to uncaught binding exceptions. Consider adding dynamic fallback configurations in the future.
