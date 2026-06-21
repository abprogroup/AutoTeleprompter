import 'dart:io';

/// Handles OS-level permission checks shared by feature entry points.
///
/// Platform behavior:
/// ┌─────────────────┬────────────────────────────────────────────────────┐
/// │ iOS             │ Requests microphone + speech recognition at use     │
/// │                 │ time, when Present/Content Creator starts STT       │
/// │ macOS           │ Same Apple speech permission model                  │
/// │ Android         │ No-op — Android permission dialogs are shown at the │
/// │                 │ point of use (when STT is first started)             │
/// │ Windows         │ No-op — Windows uses Privacy Settings, not prompts  │
/// └─────────────────┴────────────────────────────────────────────────────┘
class PlatformPermissions {
  const PlatformPermissions._();

  /// Whether this platform requires an explicit speech recognition permission
  /// dialog at session start.
  /// True on iOS and macOS (Apple requires SFSpeechRecognizer authorization).
  /// False on Android (STT permission is bundled with microphone) and Windows.
  static bool get requiresSpeechPermissionCheck =>
      Platform.isIOS || Platform.isMacOS;
}
