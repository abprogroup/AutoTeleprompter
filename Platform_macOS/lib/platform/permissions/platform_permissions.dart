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
/// │ macOS           │ No startup prompt; request native permissions at use│
/// │ Android         │ No-op — Android permission dialogs are shown at the │
/// │                 │ point of use (when STT is first started)             │
/// │ Windows         │ No-op — Windows uses Privacy Settings, not prompts  │
/// └─────────────────┴────────────────────────────────────────────────────┘
class PlatformPermissions {
  const PlatformPermissions._();

  /// Whether this platform should use the shared permission_handler speech
  /// request path at session start.
  ///
  /// macOS also requires speech authorization, but this build requests it
  /// through the native macOS bridge at the point of use. Keeping this false on
  /// macOS prevents accidental calls into the unregistered permission_handler
  /// speech backend.
  static bool get requiresSpeechPermissionCheck => Platform.isIOS;

  /// Request all permissions required by the app on the current platform.
  /// Call this once in main() before runApp().
  static Future<void> requestAll() async {
    if (Platform.isIOS) {
      await Permission.microphone.request();
      await Permission.speech.request();
      // speech_to_text's initialize() triggers the native
      // SFSpeechRecognizer.requestAuthorization() API directly.
      try {
        await SpeechToText().initialize();
      } catch (_) {}
    }
    // macOS: request permissions at point of use through the native bridge.
    // Android: STT service requests mic permission when it first starts.
    // Windows: uses system Privacy Settings, no programmatic request needed.
  }
}
