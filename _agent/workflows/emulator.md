---
description: Rebuilds the APK and deploys to the Android Emulator (emulator-5554).
---
// turbo-all

1. Verify Emulator Connection
   - Run `/Users/proapple/development/android-sdk/platform-tools/adb devices`.
   - If `emulator-5554` is NOT listed:
     - Error: "Emulator not detected. Please launch the Android Emulator before running this command."
     - Stop.

2. Perform Production Rebuild
   - Run `flutter run -d emulator-5554 --debug`.
   - **Optimization**: This command will automatically rebuild the APK if changes are detected.

3. Final Verification
   - Report "Deployment SUCCESS: App is now running on emulator-5554."
