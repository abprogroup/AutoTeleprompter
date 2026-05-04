import 'dart:io';
import 'abstract_stt_service.dart';
import 'stt_android_adapter.dart';
import 'stt_apple_adapter.dart';
import 'stt_desktop_adapter.dart';

/// Creates the correct [AbstractSttService] implementation for the
/// current runtime platform.
///
/// Platform adapter mapping:
/// - Android: SttAndroidAdapter.
/// - iOS/macOS: SttAppleAdapter.
/// - Unsupported desktop fallback: SttDesktopAdapter.
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
    // Non-Apple desktop fallback.
    return SttDesktopAdapter();
  }
}
