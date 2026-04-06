#!/bin/bash

# AutoTeleprompter v3.5.0 Surgical Precision Backup
# Purpose: Mirrors the original file path in the backups directory before editing.

PROJECT_ROOT="/Users/proapple/Desktop/AutoTeleprompter"
BACKUP_ROOT="${PROJECT_ROOT}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -z "$1" ]; then
    echo "Usage: $0 <file_path_relative_to_root>"
    exit 1
fi

REL_PATH="$1"
# Ensure we work with relative paths only
REL_PATH=$(echo "$REL_PATH" | sed "s|^$PROJECT_ROOT/||")

SOURCE_FILE="${PROJECT_ROOT}/${REL_PATH}"

if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file '$SOURCE_FILE' not found."
    exit 1
fi

BACKUP_PATH="${BACKUP_ROOT}/${TIMESTAMP}/${REL_PATH}"
BACKUP_DIR=$(dirname "$BACKUP_PATH")

mkdir -p "$BACKUP_DIR"
cp "$SOURCE_FILE" "$BACKUP_PATH"

echo "Surgical Backup created: $BACKUP_PATH"
