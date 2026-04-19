import 'dart:io';
import 'abstract_stt_service.dart';
import 'stt_android_adapter.dart';
import 'stt_apple_adapter.dart';
import 'stt_browser_adapter.dart';

/// Creates the correct [AbstractSttService] implementation for the
/// current runtime platform.
///
/// Platform → Adapter mapping:
/// ┌─────────────────┬──────────────────────────────────────────────────┐
/// │ Android         │ SttAndroidAdapter  (Google on-device via channel)│
/// │ iOS             │ SttAppleAdapter    (Apple SFSpeechRecognizer)     │
/// │ macOS           │ SttAppleAdapter    (Apple SFSpeechRecognizer)     │
/// │ Windows         │ SttDesktopAdapter  (Windows SAPI / speech_to_text)│
/// └─────────────────┴──────────────────────────────────────────────────┘
///
/// Usage:
/// ```dart
/// final _sttService = SttServiceFactory.create();
/// ```
class SttServiceFactory {
  const SttServiceFactory._();

  static AbstractSttService create() {
    if (Platform.isAndroid) return SttAndroidAdapter();
    if (Platform.isIOS || Platform.isMacOS) return SttAppleAdapter();
    // Windows: use browser Web Speech API (Edge/Chrome) via local WebSocket.
    // The Windows.Media.SpeechRecognition WinRT API is unreliable — requires
    // OS-level "Online speech recognition" setting and still fails on many machines.
    return SttBrowserAdapter();
  }
}
