---
description: Absolute Authority Ritual v3.9.5.2: Exhaustive Resource Sweep (Network, Read, Write, Command) to trigger all OS/IDE permissions upfront.
---
// turbo-all

# /clearance Ritual [AUTHORITY_GRANT] (v3.9.5.2)

This ritual is designed to "warm up" all project resources and permission categories while the USER is looking, triggering every IDE/OS prompt to ensure zero-lag execution during long-duration autonomous missions.

## [PROCEDURE]

1. **Network Sweep [NET]**
   - Execute: `read_url_content('https://www.google.com')`
   - Goal: Trigger the "Allow Network Access" IDE prompt.

2. **Read Sweep [READ]**
   - Execute: `ls -laR lib android _agent backups test`
   - Execute: `view_file('/Users/proapple/Desktop/AutoTeleprompter/AutoTeleprompter/pubspec.yaml')`
   - Execute: `view_file('/Users/proapple/Desktop/AutoTeleprompter/_agent/workflows/grant.md')`
   - Goal: Trigger "Allow Read" prompts for all core directories.

3. **Write Sweep [WRITE]**
   - Execute: `write_to_file('grant_authority_ping.tmp', 'SENTRY_V3.9.5.2_READ_WRITE_TEST_SUCCESS', false)`
   - Execute: `run_command('mv grant_authority_ping.tmp _agent/grant_authority_ping.txt')`
   - Goal: Trigger "Allow Write" and "Allow File Modification" prompts.

4. **SDK & Hardware Sweep [SDK/HW]**
   - Execute: `flutter doctor`
   - Execute: `adb devices`
   - Goal: Verify hardware bridge and SDK visibility.

5. **Declaration [TURBO]**
   - The AI agent formally declares: "Authority level 1:1 established. Autonomous Sentry Mode Active. Zero-approval mission ready for 7+ hours."

## [USER_ACTION_REQUIRED]
- during this ritual, please stay focused on the UI and click **"Always Allow"**, **"Allow Globally"**, or **"Allow for Workspace"** on every pop-up that appears.
