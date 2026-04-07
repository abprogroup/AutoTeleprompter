# AI Protocol: AutoTeleprompter v3.6.1 [LOOP_HARDEN]

## 🛡️ CORE DIRECTIVES
1. **Zero-Bypass Policy**: No code changes WITHOUT a preceding surgical backup.
2. **Terminal Sync Mandate**: README.md, MASTER_TODO.md, and DAILY_LOG.md MUST be updated via terminal `cat` to bypass UI/Sync bugs.
3. **[DUAL_BACKUP]**: 
   - **Full Snapshot**: Mandatory once at session start (`backup.sh`).
   - **Surgical Mirror**: Mandatory per-file before any edit (`pre_change_backup.sh`).
4. **[WAV] Mandate**: Workspace Access Verification is REQUIRED after loop mode selection. The AI must verify R/W/X permissions for `/lib`, `/_agent`, and `/backups`.
5. **[ATOMIC_TIMING]**: The 30-minute safety limit applies ONLY to a single task. In Mega-Loops, the timer MUST be reset (`start`) for each new TODO.

## 🚀 AUTONOMOUS ENGINE (v3.6.1)
- **Strict Consultation**: `/run` MUST stop and ask: 
  - (A) How many TODOs to fix? 
  - (B) How much time should the loop run?
- **Persistence**: `persistence_guard.sh start` must cover the entire multi-task session.

## 📄 DOCUMENTATION GOVERNANCE
- **MASTER_TODO.md**: Synchronized at the start (/plan) and end (/logit) of every loop.
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
- **`/run`**: Master autonomous loop (Planning → Execution → Verification).
- **`/fix`**: Surgical code injection of approved plans.
- **`/logit`**: Universal terminal-based documentation sync.
- **`/plan`**: Priority-based planning from MASTER_TODO.md.
- **`/test`**: Stability and regression verification.
- **`/backup`**: Surgical mirrors and full snapshots.

### **2. SAFETY & HARDWARE BRIDGE (Scripts)**
Path: `_agent/scripts/`
- **`backup.sh`**: Full project state snapshot.
- **`pre_change_backup.sh`**: Surgical per-file mirrors.
- **`persistence_guard.sh`**: Caffeinate-based session lock.
- **`task_timer.sh`**: 30-minute safety governance.
- **`emulator_bridge.sh`**: Hardware passthrough for Mac (Keyboard/Mic).

### **3. VERIFICATION**
Path: `test/`
- Centralized test artifacts and loop schemes.

### **4. GIT GOVERNANCE**
- **Commit Mandate**: All agents MUST perform a `git commit` after every successful task completion.
- **Atomic Requirement**: Commits must occur ONLY after a successful `/logit` synchronization.
- **Naming Standard**: Use the prefix `[V3-SYNC]` followed by a concise description of the fix (e.g., `git commit -m "[V3-SYNC] fixed history index sync"`).

---
*Failure to follow this consultative WAV-protected protocol will result in a hard session reset.*
