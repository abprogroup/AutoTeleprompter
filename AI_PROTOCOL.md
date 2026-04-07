# AI Protocol: AutoTeleprompter v3.7 [DEEP_FIX]

## 🛡️ CORE DIRECTIVES
1. **Zero-Bypass Policy**: No code changes WITHOUT a preceding surgical backup.
2. **Terminal Sync Mandate**: README.md, MASTER_TODO.md, and DAILY_LOG.md MUST be updated via terminal `cat` to bypass UI/Sync bugs.
3. **[DUAL_BACKUP]**: 
   - **Full Snapshot**: Mandatory once at session start (`backup.sh`).
   - **Surgical Mirror**: Mandatory per-file before any edit (`pre_change_backup.sh`).
4. **[WAV] Mandate**: Workspace Access Verification is REQUIRED after loop mode selection. The AI must verify R/W/X permissions for `/lib`, `/_agent`, and `/backups`.
5. **[ATOMIC_TIMING]**: The 30-minute safety limit applies ONLY to a single task. In Mega-Loops, the timer MUST be reset (`start`) for each new TODO.

## 🚀 AUTONOMOUS ENGINE (v3.7) [DEEP_FIX]
- **Strict Consultation**: `/deep_run` MUST stop and ask: 
  - (A) Which bug to focus on for this session?
  - (B) Clarify documentation if not complete:
    - **1. -> 2. -> 3.** (Test actions)
    - ***Wanted Result***: (The positive outcome)
    - ***Meaning***: (The core logic failure)
- **Focused Execution**: The loop now focuses on ONE bug at a time using the `/deep_fix` and `/deep_test` workflows.
- **Persistence**: `persistence_guard.sh start` must cover the entire deep-dive session.

## 📄 DOCUMENTATION GOVERNANCE
- **MASTER_TODO.md**: Synchronized at the start (/plan) and end (/logit) of every loop. Must include documented test steps for `[X]` items.
- **DAILY_LOG.md**: Real-time session history; must explicitly record the chosen Loop Mode and [WAV] status.
- **README.md**: Architectural source of truth; updated via terminal cat for bypass reliability.
- **Root Directory Cleanup**: The root directory must remain clean of `.dart` scripts or `.png` schemes. All such artifacts must reside in `/test`.

## ⚖️ VERSIONING & GOVERNANCE
1. **Stable Versioning Control**: Only the **USER** is authorized to decide when to advance to a major stable version (e.g., v3.0 to v4.0).
2. **AI Iteration Limit**: The AI is permitted to advance sub-versions (e.g., v3.4.5 to v3.4.6) to track incremental progress and surgical backups.
3. **TODO Cleanup Policy**: `[U]` (User Verified) items can ONLY be cleared during a major stable version transition, and ONLY upon explicit USER authorization.
4. **Permanent Record**: Deferred `[-]` and unresolved items (`[ ]`, `[X]`, `[F]`) must **NEVER** be deleted from the TODO list, ensuring a permanent historical record of project debt.

## ⚙️ TECHNICAL AGENTIC STRUCTURE
For external agents (Claude Code, etc.) to align with this protocol, they MUST use the project's surgical tools:

### **1. HOT COMMANDS (Workflows)**
Path: `_agent/workflows/`
- **`/deep_run`**: MASTER Focused autonomous loop (Selection → Planning → Execution → Visual Verification).
- **`/deep_fix`**: THREE-PHASE surgical fix (Research 30m, Plan 15m, Exec 15m).
- **`/deep_test`**: Visual verification via emulator screenshots and visual analysis.
- **`/logit`**: Universal terminal-based documentation sync.
- **`/plan`**: Priority-based planning from MASTER_TODO.md.
- **`/backup`**: Surgical mirrors and full snapshots.

### **2. SAFETY & HARDWARE BRIDGE (Scripts)**
Path: `_agent/scripts/`
- **`backup.sh`**: Full project state snapshot.
- **`pre_change_backup.sh`**: Surgical per-file mirrors.
- **`persistence_guard.sh`**: Caffeinate-based session lock.
- **`task_timer.sh`**: Timing governance for research/planning/exec.
- **`emulator_bridge.sh`**: Hardware passthrough for Mac (Keyboard/Mic).

### **3. VERIFICATION**
Path: `test/`
- Centralized test artifacts and visual deep analysis reports.

### **4. GIT GOVERNANCE**
- **Commit Mandate**: All agents MUST perform a `git commit` after every successful task completion.
- **Atomic Requirement**: Commits must occur ONLY after a successful `/logit` synchronization.
- **Naming Standard**: Use the prefix `[V3-SYNC]` followed by a concise description of the fix (e.g., `git commit -m "[V3-SYNC] fixed history index sync"`).

---
*Failure to follow this consultative WAV-protected deep-fix protocol will result in a hard session reset.*
