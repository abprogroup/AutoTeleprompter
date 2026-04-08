---
description: Absolute Authority Ritual: Recursive directory sweep and SDK/Hardware handshake to trigger OS/IDE permissions upfront.
---
// turbo-all

# 🛡️ Authority Grant Ritual (v3.9.5.1)

This ritual is designed to "warm up" all project resources while the USER is looking, triggering every OS and IDE-level permission prompt to ensure zero-lag execution during long-duration autonomous missions.

## [PROCEDURE]

1. **Environmental Sweep [READ]**
   - Execute `ls -laR lib android _agent backups test`.
   - Goal: Trigger the "Allow for this conversation" IDE prompt for all core directories.

2. **Handshake [SDK]**
   - Execute `flutter doctor`.
   - Execute `/Users/proapple/development/android-sdk/platform-tools/adb version`.
   - Goal: Verify toolchain connectivity and SDK folder visibility.

3. **Handshake [HARDWARE]**
   - Execute `/Users/proapple/development/android-sdk/platform-tools/adb devices`.
   - Goal: Trigger hardware bridge permissions for the emulator.

4. **Handshake [WRITE]**
   - Execute `echo "SENTRY_AUTHORITY_V3.9.5.1_GRANTED" > clearance_v3.9.5.1.tmp`.
   - Execute `mv clearance_v3.9.5.1.tmp _agent/clearance_v3.9.5.1.txt`.
   - Goal: Verify filesystem write permissions.

5. **Declaration [TURBO]**
   - The AI agent formally declares: "Authority level 1:1 established. Autonomous Sentry Mode Active. Proceeding with SafeToAutoRun: true for the next 7+ hours."

## [USER_ACTION_REQUIRED]
- during this 60-second ritual, please stay focused on the UI and click **"Always Allow"** or **"Confirm"** on any pop-ups that appear.
