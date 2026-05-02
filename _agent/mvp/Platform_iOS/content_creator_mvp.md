---
name: Content Creator MVP
type: component
platform: iOS
last_updated: 2026-04-27
---

# Content Creator MVP - iOS

Governs the dormant iOS content-creator/camera-style recording surface and any
future handoff between creator output and scripts.

## Owned Files

| File | Role |
|------|------|
| `Platform_iOS/lib/features/teleprompter/widgets/content_creator_screen.dart` | Content creator UI, lens HUD painter, recording controls placeholder |

## External API

| Method / Field | Caller |
|----------------|--------|
| `ContentCreatorScreen` | Future routing/gallery/premium entry point |
| Internal recording state | Content creator screen only |
| `_LensHUDPainter` | Content creator visual overlay |

## All Callers

| Caller | File | What it calls / reads |
|--------|------|-----------------------|
| Future gallery/premium route | `script_gallery_screen.dart` or app routing when restored | Expected to navigate to `ContentCreatorScreen` |
| Content creator screen | `content_creator_screen.dart` | Owns local recording UI state |

## Invariants

1. Content creator is dormant unless explicitly restored.
2. It must not mutate active script text without a documented import/handoff path.
3. Camera/microphone permissions must be requested through platform helpers when
   real recording is enabled.
4. Premium gating belongs to Auth/Settings/Gallery callers, not this screen.

## Forbidden Changes

- Do not enable recording or media persistence as a side effect of doc/runtime work.
- Do not write creator output into `scriptProvider` without Script Editor/File I/O ownership.
- Do not add platform permissions directly in the widget without Platform Shell review.

## Known Fragilities

- Dormant UI can drift from routing and permission expectations.
- Recording features are high-risk for platform permissions and storage.
- Visual HUD code is local and not shared with teleprompter rendering.

## Shared-File Ownership Notes

The file lives under teleprompter widgets, but creator recording is separate
from Teleprompter Engine presentation state.
