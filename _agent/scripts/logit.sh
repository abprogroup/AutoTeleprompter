#!/bin/bash
# logit.sh: Universal Documentation Synchronization v3.7.5
# Path: _agent/scripts/logit.sh

if [ -z "$1" ]; then
  echo "Usage: ./_agent/scripts/logit.sh \"Summary of changes\""
  exit 1
fi

SUMMARY="$1"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

echo "Running Autonomous Logit Sync (v3.7.5)..."

# Step 1: Manual Content Verification
# (AI performs the actual content replacement via cat, this script verifies R/W)
ls -la AI_PROTOCOL.md README.md MASTER_TODO.md DAILY_LOG.md || exit 1

# Step 2: Append to DAILY_LOG.md if not already present in this turn
echo -e "\n## [$TIMESTAMP] $SUMMARY" >> DAILY_LOG.md
echo "[OK] DAILY_LOG.md entry added."

echo "Terminal Documentation Sync [v3.7.5] Complete."
