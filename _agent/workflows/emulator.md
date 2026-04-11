---
description: Rebuilds the APK and deploys to the Android Emulator (emulator-5554).
---
// turbo-all

1. Verify Emulator Connection
   - Run `/Users/proapple/development/android-sdk/platform-tools/adb devices`.
   - If `emulator-5554` is NOT listed:
     - Error: "Emulator not detected. Please launch the Android Emulator before running this command."
     - Stop.

2. Check Application Status
   - Run `/Users/proapple/development/android-sdk/platform-tools/adb -s emulator-5554 shell pidof com.autoteleprompter.autoteleprompter`.
   - If a PID is returned:
     - Log: "AutoTeleprompter is ALREADY running. Triggering Hot Reload sync..."
     - Run `flutter run -d emulator-5554 --use-application-binary build/app/outputs/flutter-apk/app-debug.apk` (or similar if only a sync is needed).
     - *Alternative*: If the user just wants it running, report status.
   - If NO PID is returned:
     - Log: "AutoTeleprompter is NOT running. Initializing fresh launch..."
     - Run `flutter run -d emulator-5554 --debug`.

3. Final Verification
   - Report "Deployment SUCCESS: App is now running on emulator-5554."
