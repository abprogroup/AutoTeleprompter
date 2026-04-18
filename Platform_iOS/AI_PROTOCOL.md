# AI Protocol: AutoTeleprompter v3.7.5 [ABSOLUTE_VERIFICATION]

## 🛡️ CORE DIRECTIVES
1. **Zero-Bypass Policy**: No code changes WITHOUT a preceding surgical backup.
2. **Terminal Sync Mandate**: README.md, MASTER_TODO.md, and DAILY_LOG.md MUST be updated via terminal `cat` to bypass UI/Sync bugs.
3. **[DUAL_BACKUP]**: 
   - **Full Snapshot**: Mandatory once at session start (`backup.sh`).
   - **Surgical Mirror**: Mandatory per-file before any edit (`pre_change_backup.sh`).
4. **[WAV] Mandate**: Workspace Access Verification is REQUIRED after loop mode selection. The AI must verify R/W/X permissions for `/lib`, `/_agent`, and `/backups` by executing the `/clearance` authority ritual before any 7-hour autonomous session.
5. **[ATOMIC_TIMING]**: The 30-minute safety limit applies ONLY to a single task. In Mega-Loops, the timer MUST be reset (`start`) for each new TODO.

## 🚀 AUTONOMOUS ENGINE (v3.6.1) [/run]
- **Dual-Mode Loop**: Use this for broad, multi-task bug fixing.
- **Strict Consultation**: `/run` MUST stop and ask: 
  - (A) How many TODOs to fix?
  - (B) How much time should the loop run?
- **Persistence**: `persistence_guard.sh start` must cover the entire multi-task session.

## 🚀 AUTONOMOUS ENGINE (v3.7.5) [/deep_run]
- **Surgical Focus**: Use this for critical or previously-failed bugs.
- **Strict Consultation**: `/deep_run` MUST stop and ask: 
  - (A) Which bug to focus on for this session?
  - (B) Clarify documentation if not complete (Test actions, Wanted Result, Meaning).
- **Hardened Execution [ABSOLUTE_VERIFICATION]**:
  - (1) **Research [TRIO-PATH]**: Identify root cause + collect at least **THREE (3) distinct optional fix paths** before coding.
  - (2) **Test Route Planning**: Plan exact visual/logical steps to PROVE success in `test/deep_analysis/[TASK_ID]_route.md`.
  - (3) **Distinct Test Target [ANTI-MASKING]**: MUST use a high-contrast test color (e.g., **RED/MAGENTA**) that cannot be mistaken for a system highlight. **NEVER test using Yellow, White, or Amber** (System Dead-Zones).
  - (4) **Execute**: Apply the most promising fix from the Trio.
  - (5) **[MANDATORY] Rebuild**: Full APK rebuild and redeploy (`/emulator`).
  - (6) **Absolute Test [DESELECTION PROOF]**: Execute `/deep_test` with mandatory **Deselection Proof** (Screenshot MUST show the fix without active handles) and **State Sync Proof** (Re-triggering UI menu to prove choice survived).
  - (7) **Iterate [CAP=4]**: Maximum 4 autonomous loops before escalating to USER mode.
- **Environmental Reset**: If `/emulator` or APK install fails twice, AI must execute `adb kill-server && adb start-server` and a `cold-boot`.
- **Persistence**: `persistence_guard.sh start` must cover the entire deep-dive session.

## 📄 DOCUMENTATION GOVERNANCE
- **MASTER_TODO.md**: Synchronized at the start (/plan) and end (/logit) of every loop. Must include documented test steps for `[X]` items.
- **DAILY_LOG.md**: Real-time session history; must explicitly record the chosen Loop Mode and [WAV] status. **[APPEND-ONLY]**: The daily log is a cumulative historical record. When adding new entries, ALWAYS append to the existing log. NEVER remove, overwrite, or truncate entries from previous dates. All prior dates and their content must be preserved exactly as written.
- **README.md**: Architectural source of truth; updated via terminal cat for bypass reliability.
- **Surgical Updates**: When updating documentation (MASTER_TODO.md, DAILY_LOG.md, README.md), the AI must ONLY modify the specific item(s) related to the current task. Do NOT shorten, delete, or summarize unrelated items. Previous entries from earlier dates are PERMANENT and must never be removed.
- **Root Directory Governance**: The AI MUST maintain a pristine project root. Only mandatory core files (`AI_PROTOCOL.md`, `README.md`, `MASTER_TODO.md`, `DAILY_LOG.md`) are authorized to reside in the root. 
- **Dynamic Artifact Routing**: All other stray artifacts must be dynamically routed via 'Smart Understanding' to their specialized home based on type and intent:
    - **Test Proofs (PNG/MP4)**: `/test/deep_analysis/[TASK_ID]/`.
    - **Architectural Blueprints (Loop Schemes)**: `/schemes/`.
    - **Surgical Snapshots/Archives**: `/backups/`.
    - **Released Build Artifacts**: `/releases/`.
    - **Test Summary/Reports (.md)**: `/test/`.
    - **Temporary Tools/Scripts**: Must be deleted or moved to `/_agent/scripts/` after the task.
- **Visual Proof Mandate**: Every fix MUST have a `final_proof.png` in `/test` showing the fix in a stable, non-selected state.

## ⚖️ VERSIONING & GOVERNANCE
1. **Stable Versioning Control**: Only the **USER** is authorized to decide when to advance to a major stable version (e.g., v3.7.2 to v4.0.0).
2. **AI Iteration Limit**: The AI is permitted to advance sub-versions (e.g., v3.4.5 to v3.4.6) to track incremental progress and surgical backups.
3. **TODO Cleanup Policy**: `[U]` (User Verified) items can ONLY be cleared during a major stable version transition, and ONLY upon explicit USER authorization.
4. **Permanent Record**: Deferred `[-]` and unresolved items (`[ ]`, `[X]`, `[F]`) must **NEVER** be deleted from the TODO list, ensuring a permanent historical record of project debt.

## ⚙️ TECHNICAL AGENTIC STRUCTURE
For external agents (Claude Code, etc.) to align with this protocol, they MUST use the project's surgical tools:

### **1. HOT COMMANDS (Workflows)**
Path: `_agent/workflows/`
- **`/clearance`**: Absolute Authority Ritual: Recursive directory sweep and SDK/Hardware handshake to trigger OS/IDE permissions upfront.
- **`/run`**: Master Broad loop for multi-task fix sessions (Planning → Fast-Execution → Verification).
- **`/fix`**: Surgical code injection of approved plans.
- **`/deep_run`**: Focused surgical loop for critical bugs (Documentation → Test Planning → Implementation → Absolute Verification).
- **`/deep_fix`**: THREE-PHASE manual surgical fix (Research 30m, Plan 15m, Exec 15m).
- **`/deep_test`**: Hardened visual verification via Test Route execution and screenshot analysis.
- **`/emulator`**: Absolute Rebuild Mandate: Clean APK rebuild and redeployment.
- **`/logit`**: Universal terminal-based documentation sync for all project files.
- **`/plan`**: Priority-based planning from MASTER_TODO.md.
- **`/sync`**: Automatically syncs the AI agent with the AutoTeleprompter project protocols, history, and master TODO list.
- **`/test`**: Basic stability and regression verification.
- **`/test_pending`**: Autonomous verified state tracking for pending v3.6 AI tests.
- **`/organize`**: Cleans the workspace of temporary files, build logs, and test artifacts.
- **`/backup`**: Surgical mirrors and full session snapshots.

### **2. SAFETY & HARDWARE BRIDGE (Scripts)**
Path: `_agent/scripts/`
- **`backup.sh`**: Full project state snapshot.
- **`pre_change_backup.sh`**: Surgical per-file mirrors.
- **`persistence_guard.sh`**: Caffeinate-based session lock.
- **`task_timer.sh`**: Timing governance for research/planning/exec.
- **`emulator_bridge.sh`**: Hardware passthrough for Mac (Keyboard/Mic).

### **3. VERIFICATION**
Path: `test/`
- Centralized test artifacts, loop schemes and visual deep analysis reports.

### **4. GIT GOVERNANCE**
- **Commit Mandate**: All agents MUST perform a `git commit` after every successful task completion.
- **Atomic Requirement**: Commits must occur ONLY after a successful `/logit` synchronization.
- **Naming Standard**: Use the prefix `[V3-SYNC]` followed by a concise description of the fix (e.g., `git commit -m "[V3-SYNC] fixed history index sync"`).

---
*Failure to follow this consultative WAV-protected protocol will result in a hard session reset.*
