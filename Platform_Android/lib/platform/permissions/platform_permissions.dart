/// Handles OS-level permission requests at app startup.
///
/// Android: all permissions are requested at point of use (first mic access),
/// not at app launch. This class is a no-op on Android but keeps main.dart
/// symmetric with iOS / macOS which must call requestAll() at startup.
class PlatformPermissions {
  const PlatformPermissions._();

  /// Android: always false — mic permission dialog appears when STT starts,
  /// not at session launch.
  static bool get requiresSpeechPermissionCheck => false;

  /// No-op on Android. Kept for architectural symmetry with iOS/macOS.
  static Future<void> requestAll() async {
    // Android requests permissions at point of use via the STT service.
  }
}
