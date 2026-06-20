import 'dart:io';

import 'package:flutter/services.dart';

class ExternalUrlLauncher {
  const ExternalUrlLauncher._();

  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/system');
  static Future<ProcessResult> Function(String, List<String>)
      _fallbackProcessRunner = Process.run;

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
    try {
      final result = await _fallbackProcessRunner('/usr/bin/open', [target])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static void debugSetFallbackProcessRunnerForTests(
    Future<ProcessResult> Function(String, List<String>)? runner,
  ) {
    _fallbackProcessRunner = runner ?? Process.run;
  }
}
