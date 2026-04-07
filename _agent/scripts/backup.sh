#!/bin/bash

# AutoTeleprompter v3.4.0 Backup Utility
# Purpose: Creates a timestamped archive of the source code.

BACKUP_DIR="/Users/proapple/Desktop/AutoTeleprompter/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="autoteleprompter_backup_${TIMESTAMP}.tar.gz"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "Creating backup: ${ARCHIVE_NAME}..."

# Exclude large/binary directories to keep backups slim
tar --exclude='build' \
    --exclude='.dart_tool' \
    --exclude='.android' \
    --exclude='.gradle' \
    --exclude='backups' \
    --exclude='.git' \
    -czf "${BACKUP_DIR}/${ARCHIVE_NAME}" -C /Users/proapple/Desktop/AutoTeleprompter .

if [ $? -eq 0 ]; then
    echo "Backup successful: ${BACKUP_DIR}/${ARCHIVE_NAME}"
    exit 0
else
    echo "ERROR: Backup failed!"
    exit 1
fi
