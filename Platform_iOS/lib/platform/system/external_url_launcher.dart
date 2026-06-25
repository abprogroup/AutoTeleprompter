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
    final absolute = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    // iOS has no Finder. The Files app responds to the `shareddocuments`
    // scheme to reveal a folder the app can access (its own container or an
    // iCloud Drive / On My iPhone location the user picked).
    for (final candidate in <String>[
      'shareddocuments://$absolute',
      'shareddocuments://${Uri.encodeFull(absolute)}',
    ]) {
      final uri = Uri.tryParse(candidate);
      if (uri == null) continue;
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Try the next candidate / fall through.
      }
    }
    try {
      final fileUri = Uri.file(trimmed);
      if (await canLaunchUrl(fileUri)) {
        return await launchUrl(fileUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
    return false;
  }
}
