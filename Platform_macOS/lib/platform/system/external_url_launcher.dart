import 'dart:io';

import 'package:flutter/services.dart';

class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/system');

  static Future<bool> openUrl(String url) {
    return _open(url, filePath: false);
  }

  static Future<bool> openPath(String path) {
    return _open(path, filePath: true);
  }

  static Future<bool> _open(String target, {required bool filePath}) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openExternalUrl', {
            'target': target,
            'filePath': filePath,
          }) ??
          false;
      if (opened) return true;
    } catch (_) {
      // Fall through to /usr/bin/open if the native channel is unavailable.
    }
    final result = await Process.run('/usr/bin/open', [target]);
    return result.exitCode == 0;
  }
}
