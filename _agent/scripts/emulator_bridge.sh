#!/bin/bash

# AutoTeleprompter v4.1 Emulator Hardware Bridge (macOS)
# Purpose: Deep Force Mac hardware connectivity (Keyboard/Mic/Camera).
# v4.1: Improved AVD config patching with regex, robust ADB path, and modernized audio triggers.

echo "🚀 Starting AutoTeleprompter 'Deep Stability' Hardware Bridge v4.1..."

# 1. Locate ADB
ADB_PATH=$(which adb)
if [ -z "$ADB_PATH" ]; then
    PATHS=(
        "/Users/proapple/development/android-sdk/platform-tools/adb"
        "$HOME/Library/Android/sdk/platform-tools/adb"
        "/usr/local/bin/adb"
        "/opt/homebrew/bin/adb"
    )
    for p in "${PATHS[@]}"; do
        if [ -f "$p" ]; then
            ADB_PATH="$p"
            break
        fi
    done
fi

if [ -z "$ADB_PATH" ]; then
    echo "❌ [ERROR] 'adb' not found." && exit 1
fi

echo "📍 Using ADB: $ADB_PATH"

# 2. Patch AVD config.ini to enable physical keyboard
AVD_DIR="$HOME/.android/avd"
if [ -d "$AVD_DIR" ]; then
    for avd_path in "$AVD_DIR"/*.avd; do
        if [ -d "$avd_path" ]; then
            CONFIG="$avd_path/config.ini"
            if [ -f "$CONFIG" ]; then
                AVD_NAME=$(basename "$avd_path" .avd)

                # Robust Patching Function
                patch_config() {
                    local key=$1
                    local value=$2
                    if grep -q "^${key}\s*=" "$CONFIG"; then
                        sed -i '' "s/^${key}\s*=.*/${key} = ${value}/" "$CONFIG"
                    else
                        echo "${key} = ${value}" >> "$CONFIG"
                    fi
                }

                patch_config "hw.keyboard" "yes"
                patch_config "hw.audioInput" "yes"
                patch_config "hw.audioOutput" "yes"
                patch_config "hw.mainKeys" "no"
                patch_config "fastboot.forceColdBoot" "yes"

                echo "✅ [AVD] Patched config for: $AVD_NAME (keyboard=yes, audio=yes, cold_boot=yes)"
            fi
        fi
    done
else
    echo "⚠️ [WARN] AVD directory not found at $AVD_DIR"
fi

DEVICES=$($ADB_PATH devices | grep -v "List" | awk '{print $1}' | xargs)
PACKAGE="com.autoteleprompter.autoteleprompter"

if [ -z "$DEVICES" ]; then
    echo "⚠️ [WARN] No active emulator detected. Config changes applied, but runtime bridge skipped."
    echo "👉 PLEASE START YOUR EMULATOR NOW (Cold Boot recommended)."
    exit 0
fi

for DEV in $DEVICES; do
    echo "🔗 Forcing Mac-to-Emulator Bridge on: $DEV"

    # 3. Permissions (Mic/Camera)
    echo "   - Granting permissions..."
    $ADB_PATH -s $DEV shell pm grant $PACKAGE android.permission.RECORD_AUDIO 2>/dev/null
    $ADB_PATH -s $DEV shell pm grant $PACKAGE android.permission.CAMERA 2>/dev/null

    # 4. FORCE MAC KEYBOARD (Physical) + Hebrew Support
    echo "   - Configuring Keyboard & IME..."
    # show_ime_with_hard_keyboard: Show software keyboard alongside physical
    $ADB_PATH -s $DEV shell settings put secure show_ime_with_hard_keyboard 1 2>/dev/null

    # Enable physical keyboard in the emulator runtime
    $ADB_PATH -s $DEV shell setprop qemu.hw.mainkeys 0 2>/dev/null

    # Force Hebrew IME subtype (18 is common for LatinIME/Gboard Hebrew)
    # We also attempt to ensure Hebrew is in the enabled list
    ENABLED_IMES=$($ADB_PATH -s $DEV shell settings get secure enabled_input_methods)
    if [[ ! "$ENABLED_IMES" == *"iw"* ]] && [[ ! "$ENABLED_IMES" == *"he"* ]]; then
        echo "   - Warning: Hebrew might not be enabled in Gboard settings."
    fi
    $ADB_PATH -s $DEV shell settings put secure selected_input_method_subtype 18 2>/dev/null

    # 5. FORCE AUDIO INITIALIZATION (Modern Android)
    echo "   - Initializing Audio Passthrough..."
    $ADB_PATH -s $DEV shell settings put global audio_safe_volume_state 3 2>/dev/null
    
    # Modern triggers for audio policy
    $ADB_PATH -s $DEV shell cmd media.audio_policy set-force-use FOR_RECORD FORCE_NONE 2>/dev/null
    $ADB_PATH -s $DEV shell cmd media.audio_policy set-force-use FOR_RECORD FORCE_SYSTEM_ENFORCED 2>/dev/null

    echo "✅ [SUCCESS] Bridged $DEV."
done

echo ""
echo "📱 [COMMANDS APPLIED]"
echo "- AVD Config: hw.keyboard=yes, hw.audioInput=yes, fastboot.forceColdBoot=yes"
echo "- Physical Keyboard: FORCED ON"
echo "- Hebrew IME Sync: TRIGGERED (Subtype 18)"
echo "- Audio Input: HOST MIC ROUTING TRIGGERED"
echo ""
echo "⚠️ [IMPORTANT NEXT STEPS]"
echo "1. If the emulator was already RUNNING, you MUST COLD BOOT it for config changes to apply."
echo "   → Quit Emulator → AVD Manager → Actions → Cold Boot Now"
echo "2. In Emulator: Settings > System > Languages > Hebrew (Ensure it is at the top)."
echo "3. Verify Mic: Extended Controls (⋮) > Microphone > Toggle 'Virtual microphone uses host audio input' ON/OFF."

