#!/bin/bash

# AutoTeleprompter v3.7.5 Persistence Guard
# Purpose: Maintains session active state via caffeinate (Mac).

PID_FILE="/tmp/.agent_persistence_guard.pid"

case "$1" in
    start)
        # Check if already running
        if [ -f "$PID_FILE" ]; then
            OLD_PID=$(cat "$PID_FILE")
            if ps -p "$OLD_PID" > /dev/null; then
                echo "Persistence Guard already active (PID $OLD_PID)."
                exit 0
            fi
            rm -f "$PID_FILE"
        fi
        # -m: disk, -i: idle, -s: system, -d: display
        # We use a background process
        caffeinate -m -i -s -d & 
        NEW_PID=$!
        echo "$NEW_PID" > "$PID_FILE"
        echo "Persistence Guard active (caffeinate PID $NEW_PID)."
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            TARGET_PID=$(cat "$PID_FILE")
            if ps -p "$TARGET_PID" > /dev/null 2>&1; then
                kill "$TARGET_PID"
                echo "Persistence Guard stopped (caffeinate PID $TARGET_PID terminated)."
            else
                echo "No active caffeinate process found for PID $TARGET_PID."
            fi
            rm -f "$PID_FILE"
        else
            echo "Persistence Guard is already stopped (No PID file)."
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ]; then
            TARGET_PID=$(cat "$PID_FILE")
            if ps -p "$TARGET_PID" > /dev/null; then
                echo "Persistence Guard is RUNNING (PID $TARGET_PID)."
            else
                echo "Persistence Guard is STALE (PID file exists, but process is dead)."
            fi
        else
            echo "Persistence Guard is STOPPED."
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
