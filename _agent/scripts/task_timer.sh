#!/bin/bash

# AutoTeleprompter v3.7.5 Task Timer
# Purpose: Prevents autonomous thashing by enforcing a 30-minute limit per task.

TIMER_FILE="/Users/proapple/.agent_task_start"
MAX_SECONDS=1800 # 30 minutes

case "$1" in
    start)
        date +%s > "$TIMER_FILE"
        echo "Timer started at $(date)"
        ;;
    check)
        if [ ! -f "$TIMER_FILE" ]; then
            # If no timer exists, we don't block, but warn.
            echo "Warning: No active timer found. Use '$0 start' to begin tracking."
            exit 0
        fi
        START_TIME=$(cat "$TIMER_FILE")
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        
        if [ "$ELAPSED" -gt "$MAX_SECONDS" ]; then
            echo "CRITICAL: Task timeout exceeded! ($ELAPSED seconds elapsed / 1800 max)."
            echo "Stopping execution for manual review."
            exit 1
        else
            REMAINING=$((MAX_SECONDS - ELAPSED))
            echo "Timer OK: $ELAPSED seconds elapsed ($REMAINING remaining)."
            exit 0
        fi
        ;;
    remaining)
        if [ ! -f "$TIMER_FILE" ]; then
            echo "0"
            exit 0
        fi
        START_TIME=$(cat "$TIMER_FILE")
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - START_TIME))
        REMAINING=$((MAX_SECONDS - ELAPSED))
        if [ "$REMAINING" -lt 0 ]; then echo "0"; else echo "$REMAINING"; fi
        ;;
    clear)
        rm -f "$TIMER_FILE"
        echo "Timer cleared."
        ;;
    *)
        echo "Usage: $0 {start|check|clear}"
        exit 1
        ;;
esac
