# Fix iOS Build: Forcing Package Upgrade

The build failed one more time because the cloud runner was stubborn! It was still using the broken version of a package (`google_fonts`) by following the old "lock file" instead of our new instructions.

## User Review Required

> [!NOTE]
> **Forced Upgrade:** I am changing the build instructions to "Forced Upgrade." This tells the cloud Mac to ignore the old lock file and grab the newest fixed versions of everything. 
> **iTunes for PC:** This is still needed! I've explained below why Windows needs these specific Apple drivers to "talk" to your iPhone hardware.

## Proposed Changes

### ⚙️ Build Pipeline

#### [MODIFY] [.github/workflows/build-ios.yml](file:///c:/Users/AMIT-BAR/.github/workflows/build-ios.yml)
Change `flutter pub get` to `flutter pub upgrade`. This ensures the cloud runner picks up the version fix we applied.

### 🛠️ Flutter Dependencies

#### [MODIFY] [pubspec.yaml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/AutoTeleprompter/pubspec.yaml)
Explicitly pin `google_fonts` to `6.3.1` (removing the `^`) to force the correct version.

## Implementation Steps

1. **Update pubspec.yaml**: Lock the version strictly.
2. **Update workflow**: Switch to `pub upgrade`.
3. **Commit and Push**: Trigger the build again.

## Verification Plan

### Automated Tests
- I will verify in the logs that `google_fonts` version `6.3.1` is being used.

### Manual Verification
- You will see the device appear in Sideloadly after installing the Standalone iTunes.
