import 'dart:io';

import 'package:flutter/services.dart';

import 'update_check_service.dart';

/// Hands a downloaded update APK off to Android's system package installer.
///
/// Unlike Windows (which exits the running process and robocopies a new
/// build over the current install), Android apps cannot replace their own
/// installed package from inside the running process. The platform-correct
/// approach - and the only one Android supports for a sideloaded APK - is to
/// launch an `ACTION_VIEW` intent on a `content://` URI (via FileProvider)
/// with the APK MIME type. This hands control to the OS installer UI, which
/// itself requires the user's explicit confirmation (and, on first use, an
/// explicit "allow installs from this app" grant) - satisfying the "user
/// consent before install" invariant in `update_system_mvp.md` by
/// construction, not by app-side logic.
///
/// NOT verified on a real device/emulator - this environment cannot launch
/// the Android package installer to confirm the intent actually resolves and
/// completes. See `update_system_mvp.md` for what a device pass must check.
class UpdateInstallService {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/android_files');

  Future<void> installDownloadedUpdate(
    File file,
    UpdateCheckResult result,
  ) async {
    if (!await file.exists()) {
      throw StateError('Downloaded update file is missing: ${file.path}');
    }
    final launched = await _channel.invokeMethod<bool>(
      'installApk',
      {'path': file.path},
    );
    if (launched != true) {
      throw StateError('Could not launch the Android package installer.');
    }
  }
}
