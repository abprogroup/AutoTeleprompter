# Final "Rock Solid" Fix: iOS Build Finalization

I have performed a deep-log analysis of the Beta build. It turns out the "Font Error" is so persistent that it even crashes the experimental Beta version of Flutter. This is a known issue where the `google_fonts` package is currently "broken" across all modern versions of Flutter due to a change in the Dart language.

## User Review Required

> [!IMPORTANT]
> **Rock Solid Downgrade:** I am downgrading `google_fonts` to version `5.1.0`. 
> **Why?** This older version does not use the specific "Constant Map" feature that changed in Dart 3.5. By going back to this stable foundation, we bypass the bug entirely and allow the compiler to finish the app.
> **Stable Ground:** I am moving the cloud build back to the **Stable Channel**. Now that I've found the true culprit, we can return to the safest environment.

## Proposed Changes

### ⚙️ Build Pipeline

#### [MODIFY] [.github/workflows/build-ios.yml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/.github/workflows/build-ios.yml)
Return the channel to `stable` and lock the version to `3.24.3`.

### 🛠️ Flutter Dependencies

#### [MODIFY] [pubspec.yaml](file:///c:/Users/AMIT-BAR/AutoTeleprompter/AutoTeleprompter/pubspec.yaml)
Pin `google_fonts` strictly to `5.1.0`.

## Implementation Steps

1. **Update pubspec.yaml**: Lock the package to the pre-bug version.
2. **Update Workflow**: Return to Stable environment.
3. **Commit and Push**: Trigger the definitive build.

## Verification Plan

### Automated Tests
- I will verify the code compiles without the "FontWeight primitive equality" error.

### Manual Verification
- You will finally get the app on your phone!
