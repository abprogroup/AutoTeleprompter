# AI Protocol: AutoTeleprompter v3.6.1 [DUAL_BACKUP]

## 🛡️ CORE DIRECTIVES
1. **Zero-Bypass Policy**: No code changes WITHOUT a preceding surgical backup.
2. **Terminal Sync Mandate**: README.md, MASTER_TODO.md, and DAILY_LOG.md MUST be updated via terminal `cat` to bypass UI/Sync bugs.
3. **[DUAL_BACKUP]**: 
   - **Full Snapshot**: Mandatory once at session start (`backup.sh`).
   - **Surgical Mirror**: Mandatory per-file before any edit (`pre_change_backup.sh`).
4. **[ATOMIC_TIMING]**: The 30-minute safety limit applies ONLY to a single task. In Mega-Loops, the timer MUST be reset (`start`) for each new TODO.

## 🚀 AUTONOMOUS ENGINE (v3.6.1)
- **Strict Consultation**: `/run` MUST stop and ask: 
  - (A) How many TODOs to fix? 
  - (B) How much time should the loop run?
- **Persistence**: `persistence_guard.sh start` must cover the entire multi-task session.

## 📄 DOCUMENTATION GOVERNANCE
- **MASTER_TODO.md**: Synchronized at the start (/plan) and end (/logit) of every loop.
- **DAILY_LOG.md**: Real-time session history; must explicitly record the chosen Loop Mode.
- **README.md**: Architectural source of truth; updated via terminal cat for bypass reliability.

---
*Failure to follow this consultative dual-backup protocol will result in a hard session reset.*
