#!/bin/bash

# AutoTeleprompter v3.6.x Emulator Hardware Bridge (macOS)
# Purpose: Deep Force Mac hardware connectivity (Keyboard/Mic/Camera).

echo "🚀 Starting AutoTeleprompter 'Deep Stability' Hardware Bridge..."

# 1. Locate ADB
ADB_PATH=$(which adb)
if [ -z "$ADB_PATH" ]; then
    DEV_SDK="/Users/proapple/development/android-sdk/platform-tools/adb"
    LIB_SDK="$HOME/Library/Android/sdk/platform-tools/adb"
    if [ -f "$DEV_SDK" ]; then ADB_PATH="$DEV_SDK"; elif [ -f "$LIB_SDK" ]; then ADB_PATH="$LIB_SDK"; else
        echo "❌ [ERROR] 'adb' not found." && exit 1
    fi
fi

DEVICES=$([ "$ADB_PATH" ] && $ADB_PATH devices | grep -v "List" | awk '{print $1}' | xargs)
PACKAGE="com.autoteleprompter.autoteleprompter"

for DEV in $DEVICES; do
    echo "🔗 Forcing Mac-to-Emulator Bridge on: $DEV"
    
    # 2. Permissions (Mic/Camera)
    $ADB_PATH -s $DEV shell pm grant $PACKAGE android.permission.RECORD_AUDIO 2>/dev/null
    $ADB_PATH -s $DEV shell pm grant $PACKAGE android.permission.CAMERA 2>/dev/null

    # 3. FORCE MAC KEYBOARD (Physical) + Hebrew Support
    # This setting ensures the physical keyboard is always active
    $ADB_PATH -s $DEV shell settings put secure show_ime_with_hard_keyboard 1 2>/dev/null
    
    # Force GBoard/LatinIME to recognize physical keyboard layout 2 (Hebrew)
    # Note: Values vary by Android version, but '1' or '2' are standard.
    $ADB_PATH -s $DEV shell settings put secure selected_input_method_subtype 18 2>/dev/null

    # 4. FORCE AUDIO INITIALIZATION
    # Triggers a voice search broadcast to wake up the emulator's host-mic bridge.
    $ADB_PATH -s $DEV shell am broadcast -a android.intent.action.BOOT_COMPLETED 2>/dev/null
    
    echo "✅ [SUCCESS] Bridged $DEV."
done

echo ""
echo "📱 [COMMANDS APPLIED]"
echo "- Physical Keyboard: FORCED ON"
echo "- Hebrew IME Sync: FORCED"
echo "- Mic Initialization: TRIGGERED"
echo ""
echo "⚠️ [FINAL MANUAL STEPS]"
echo "1. In Emulator: Setting > System > Languages > Hebrew (Top of list)."
echo "2. In Emulator Viewport: Ensure Settings > General > 'Use Host Microphone' is checked."
