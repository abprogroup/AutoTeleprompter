---
description: Orchestrates 4 types of project backups — full project, platform, surgical file, and version seal.
---
# /backup Workflow

Always ask the user which type of backup they want before proceeding.

---

## Type 1 — Full Project Backup
Archives the entire repository including releases, planning, and development folders.

**When to use:** End-of-session safety net, before major restructuring, or when explicitly requested.

**Naming:** `full_project_backup_YYYYMMDD_HHMMSS.tar.gz`

```bash
./_agent/scripts/backup_full.sh
```

**Excludes:** `build/`, `.dart_tool/`, `.android/`, `.gradle/`, `backups/`, `.git/`

---

## Type 2 — Platform Backup
Archives a single platform folder only.

**When to use:** Before making significant changes to one platform, or after sealing development on a platform.

**Naming:** `platform_[ios|android|windows|macos]_backup_YYYYMMDD_HHMMSS.tar.gz`

**Ask the user:** Which platform? (ios / android / windows / macos)

```bash
./_agent/scripts/backup_platform.sh <platform>
# Example: ./_agent/scripts/backup_platform.sh ios
```

---

## Type 3 — Surgical File Backup
Backs up specific files before modifying them, preserving full directory path so they can be restored exactly.

**When to use:** Before any deep fix or multi-step change to specific files. Called automatically by `/fix` and `/deep_fix` loops.

**Naming:** Files are mirrored inside `backups/surgical/YYYYMMDD_HHMMSS/` with their full relative path preserved.

```bash
./_agent/scripts/backup_surgical.sh <file_path> [file_path2] ...
# Example: ./_agent/scripts/backup_surgical.sh Platform_Windows/lib/features/teleprompter/services/speech_service.dart
```

**Restore:** Copy the file from `backups/surgical/TIMESTAMP/` back to its original path.

---

## Type 4 — Seal Backup
Creates a permanent, version-tagged archive at the exact moment a platform version is sealed. Never overwritten.

**When to use:** When declaring a platform version as sealed/stable. This is the authoritative source of truth for that version.

**Naming:** `[platform]_v[version]_sealed_YYYYMMDD_HHMMSS.tar.gz`

**Ask the user:** Which platform and version? (e.g. ios v4.1.4 / android v4.0)

```bash
./_agent/scripts/backup_seal.sh <platform> <version>
# Example: ./_agent/scripts/backup_seal.sh ios 4.1.4
```

---

> [!IMPORTANT]
> The `backups/` folder is gitignored and must NEVER be committed to git.
> Backup scripts must always exclude the `backups/` folder itself to prevent recursive archives.
