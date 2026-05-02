# Fix iOS Build: Plugin Stabilization

I have found the **Deep Technical Error** hiding in the logs! 🔍 
The `wakelock_plus` plugin (the part that keeps your screen from turning off) has a bug in its latest version that causes the iOS build to crash with a "File Not Found" error.

## User Review Required

> [!IMPORTANT]
> **Plugin Adjustment:** I am going to lock the `wakelock_plus` plugin to a known stable version (`1.2.8`). This fixes a bug in their native Mac code that was causing the "messages.g.h" file to go missing during the build.

## Proposed Changes

### 🛠️ Flutter Dependencies

#### [MODIFY] [pubspec.yaml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/AutoTeleprompter/pubspec.yaml)
Lock `wakelock_plus` to version `1.2.8` instead of allowing it to auto-update to the broken version.

### ⚙️ Build Pipeline

#### [MODIFY] [.github/workflows/build-ios.yml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/.github/workflows/build-ios.yml)
Add a "Clean" step to ensure no old, broken files are left in the cloud cache.

## Implementation Steps

1. **Update pubspec.yaml**: Lock the problematic plugin version.
2. **Improve Workflow**: Add `flutter clean` for a fresh build environment.
3. **Commit and Push**: Fire one more attempt to the cloud.
4. **Final Automation**: Your script will continue to watch and download once this succeeds.

## Verification Plan

### Automated Tests
- I will monitor the log specifically for the `wakelock_plus` build step to ensure it passes.

### Manual Verification
- The `Automate-iOS.ps1` script will finish and deliver the app to your Desktop.
