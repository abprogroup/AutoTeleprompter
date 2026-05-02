---
name: Remote MVP
type: component
platform: iOS
last_updated: 2026-04-27
---

# Remote MVP - iOS

Governs the dormant local remote-control service for iOS. It exposes an HTTP
page and WebSocket command stream for local-network teleprompter controls when
remote features are enabled.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/remote/services/remote_control_service.dart` | `RemoteControlService`, port 8080 HTTP server, `/` page, `/ws` WebSocket, broadcast `onCommand`, `remoteControlProvider` |
| `Platform_iOS/lib/features/teleprompter/widgets/teleprompter_screen.dart` | Remote command subscription and command-to-teleprompter/settings mapping |

## External API

| Method / Field | Caller |
|----------------|--------|
| `remoteControlProvider` | Teleprompter screen/provider code |
| `RemoteControlService.start()` | Future restored remote lifecycle |
| `RemoteControlService.stop()` | Future lifecycle disposal |
| `RemoteControlService.onCommand` | `TeleprompterScreen` remote subscription |
| HTTP `GET /` | Browser/phone remote page |
| WebSocket `GET /ws` | Browser/phone command channel |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Teleprompter screen | `teleprompter_screen.dart` | Listens to `onCommand` and maps commands |
| Remote web client | HTML served by `remote_control_service.dart` | Sends `TOGGLE`, `FASTER`, `SLOWER`, `RESET`, `MODE_MANUAL`, `MODE_AUTO` |
| Future remote dashboard | Gallery/settings when restored | Expected to call `start()`, `stop()`, and show status |

## Invariants

1. Port `8080` is the remote-control port; do not reuse it for STT.
2. Remote service emits raw command strings only; scroll state remains outside
   the service.
3. The command stream must remain broadcast so UI and future dashboards can
   coexist.
4. Server cleanup must close `_server` and release the port.
5. LAN exposure is real when binding to `InternetAddress.anyIPv4`.

## Forbidden Changes

- Do not move teleprompter state into `RemoteControlService`.
- Do not merge remote WebSocket traffic with STT/browser services.
- Do not add privileged remote actions without authentication or local-only limits.

## Known Fragilities

- Port 8080 may collide with other services.
- iOS local-network permissions/firewall behavior can block discovery.
- Remote is dormant, so callbacks can drift silently.

## Shared-File Ownership Notes

Remote owns only remote subscription and command mapping inside
`teleprompter_screen.dart`; presentation state belongs to Teleprompter Engine.
