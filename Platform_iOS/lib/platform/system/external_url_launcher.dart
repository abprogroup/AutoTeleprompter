import 'package:url_launcher/url_launcher.dart';

/// iOS implementation of the desktop `ExternalUrlLauncher` API used by shared
/// feature code (notably the cloud sync screen). On desktop this shelled out to
/// the OS file opener; on iOS we route URLs through url_launcher. Opening a
/// raw local folder path is not a supported iOS concept, so [openPath] attempts
/// a best-effort file URI and reports failure gracefully to callers.
class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;
    try {
      final uri = Uri.file(trimmed);
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
