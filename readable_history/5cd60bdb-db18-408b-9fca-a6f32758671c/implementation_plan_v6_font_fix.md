# Fix iOS Build: Font Capability & iPhone Connection

I've found the **latest technical roadblock!** 🛑 
A specific package in your project (`google_fonts`) is having a "version fight" with the latest Flutter compiler in the cloud.

## User Review Required

> [!IMPORTANT]
> **Dependency Upgrade:** I am upgrading the `google_fonts` package from `^6.2.1` to `^6.3.1`. This is required to fix a specific bug in Dart which was causing the "FontWeight" error we saw in the logs.
> **iPhone Drivers:** To fix your "No device detected" issue, you will likely need to re-install iTunes using the **Standalone Link** (not the Microsoft Store version). I will provide the link below.

## Proposed Changes

### 🛠️ Flutter Dependencies

#### [MODIFY] [pubspec.yaml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/AutoTeleprompter/pubspec.yaml)
Upgrade `google_fonts` to `^6.3.1`.

## Implementation Steps

1. **Update pubspec.yaml**: Apply the version upgrade.
2. **Commit and Push**: Trigger the fresh build.
3. **iPhone Connection Guide**: Provide the "Standard iTunes" fix for Windows.

## Open Questions

> [!CAUTION]
> **How did you install iTunes?**
> If you got it from the "Windows Store" (Microsoft Store), that is usually why Sideloadly can't see your phone. Standard Apple drivers are needed.

## Verification Plan

### Automated Tests
- I will check that the `Build iOS` step gets past the kernel snapshot phase.

### Manual Verification
- Your automation script will finally succeed and open the artifact for you.
