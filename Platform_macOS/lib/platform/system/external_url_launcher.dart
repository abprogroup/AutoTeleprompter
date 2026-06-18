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
    if (Platform.isMacOS) {
      return await _channel.invokeMethod<bool>('openExternalUrl', {
            'target': target,
            'filePath': filePath,
          }) ??
          false;
    }
    if (Platform.isWindows) {
      final result = await Process.run('cmd', [
        '/c',
        'start',
        '',
        target,
      ]);
      return result.exitCode == 0;
    }
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [target]);
      return result.exitCode == 0;
    }
    return false;
  }
}
