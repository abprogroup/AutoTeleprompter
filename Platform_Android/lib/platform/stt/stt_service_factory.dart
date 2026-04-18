import 'abstract_stt_service.dart';
import 'stt_android_adapter.dart';

/// Creates the STT service for the Android platform.
///
/// No Platform.isXxx check needed — this codebase only runs on Android.
/// Platform_iOS and Platform_Windows have their own factories.
class SttServiceFactory {
  const SttServiceFactory._();

  static AbstractSttService create() => SttAndroidAdapter();
}
