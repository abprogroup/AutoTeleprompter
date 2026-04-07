# Bridge Status Report: v3.6.2 [V3-SYNC]

## 🛠️ Configuration Applied
The following hardware bridge parameters have been successfully injected into the AVD configuration:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `hw.keyboard` | `yes` | Enable Mac physical keyboard |
| `hw.audioInput` | `yes` | Enable host microphone |
| `hw.audioOutput` | `yes` | Enable host audio output |
| `hw.mainKeys` | `no` | Clean UI (Soft keys) |
| `fastboot.forceColdBoot` | `yes` | Force hardware refresh on boot |

## 🔗 Runtime ADB Commands
The following bridge commands were executed on `emulator-5554`:

1. **Permissions**: `RECORD_AUDIO` and `CAMERA` granted.
2. **Keyboard**: `show_ime_with_hard_keyboard` set to `1`.
3. **IME**: `selected_input_method_subtype` set to `18` (Hebrew Trigger).
4. **Audio**: `media.audio_policy set-force-use` applied for routing.

## 🚀 Status: PRE-READY
> [!IMPORTANT]
> **Action Required**: The changes are staged. You **MUST** perform a **Cold Boot** for the keyboard and mic to activate.

### How to Cold Boot:
1. **Quit** the emulator.
2. Open **Android Studio** > **Device Manager** (or AVD Manager).
3. Find `AutoTeleprompt_Test`.
4. Click the **dropdown arrow** (⋮) next to the Play button.
5. Select **Cold Boot Now**.
