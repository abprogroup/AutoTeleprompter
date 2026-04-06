# AI Protocol: AutoTeleprompter v3.0.0

This protocol is **MANDATORY** for all AI agents (Claude, Antigravity, or others) interacting with this repository. Read this FIRST in every new conversation.

### 1. Mandatory Context Sync
Before making any changes, you MUST read the following:
- **`development/PROJECT_RECORDS.md`**: For the changelog and backlog of needed fixes.
- **`releases/README.md`**: For the folder organization rules.
- **`README.md` (Root)**: For the overall project overview.

### 2. Core Repository Rules
- **COMPILED ONLY**: Strictly no source code (lib, android, ios, etc.) allowed inside the `/releases/` subfolders. Only binaries (APK, IPA) permitted.
- **FULL NAMES**: Always refer to the project as "AutoTeleprompter".
- **BACKUPS**: The `/backups/` folder must never be tracked in Git.

### 3. Change Tracking
- **LOGGING**: Every session MUST conclude with an update to `development/PROJECT_RECORDS.md` (this replaces the old `DAILY_LOG.md` and `MASTER_TODO.md`).
- **COMMIT MESSAGE**: Use clear prefixes like `[V3-UI]`, `[V3-FIX]`, or `[V3-DOCS]`.

### 4. Code Principles
- **No Side-Files**: Fix bugs in the active `AutoTeleprompter/` folder. Do not create experimental branches or folders unless specifically requested.

### 5. Verification Sovereignty (Zero-Bypass)
- **Automated Verification**: A task is ONLY complete if the `/test` workflow executes a verification command (e.g., `flutter analyze`) to completion.
- **Fail = Incomplete**: If a tool is missing, a path is broken, or a command fails, the task **MUST NOT** be marked as `[x]` in `MASTER_TODO.md`.
- **Environment Failure**: If a tool cannot be found, document the failure in `AI_PROPOSAL.md` and stop automated operations immediately. Do not "manual check" and mark success.

---
*Authorized by: PROJECT_PROTOCOL v1.2*
