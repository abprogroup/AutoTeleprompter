import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Handles OS-level permission requests at app startup.
///
/// Platform behavior:
/// ┌─────────────────┬────────────────────────────────────────────────────┐
/// │ iOS             │ Requests microphone + speech recognition at launch  │
/// │                 │ Also calls SpeechToText().initialize() to trigger   │
/// │                 │ the native SFSpeechRecognizer.requestAuthorization()│
/// │ macOS           │ Same as iOS — macOS also uses SFSpeechRecognizer    │
/// │ Android         │ No-op — Android permission dialogs are shown at the │
/// │                 │ point of use (when STT is first started)             │
/// │ Windows         │ No-op — Windows uses Privacy Settings, not prompts  │
/// └─────────────────┴────────────────────────────────────────────────────┘
class PlatformPermissions {
  const PlatformPermissions._();

  /// Whether this platform requires an explicit speech recognition permission
  /// dialog at session start (in addition to the startup request).
  /// True on iOS and macOS (Apple requires SFSpeechRecognizer authorization).
  /// False on Android (STT permission is bundled with microphone) and Windows.
  static bool get requiresSpeechPermissionCheck =>
      Platform.isIOS || Platform.isMacOS;

  /// Request all permissions required by the app on the current platform.
  /// Call this once in main() before runApp().
  static Future<void> requestAll() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await Permission.microphone.request();
      await Permission.speech.request();
      // speech_to_text's initialize() triggers the native
      // SFSpeechRecognizer.requestAuthorization() API directly,
      // which is required for the permission to appear in iOS/macOS Settings.
      try {
        await SpeechToText().initialize();
      } catch (_) {}
    }
    // Android: STT service requests mic permission when it first starts.
    // Windows: uses system Privacy Settings, no programmatic request needed.
  }
}
