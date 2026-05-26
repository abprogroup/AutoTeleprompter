import 'dart:io';

import 'package:flutter/services.dart';

class PresenterFullscreenService {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/window');

  static Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return enabled;
    }
    final applied = await _channel.invokeMethod<bool>(
      'setPresenterFullscreen',
      enabled,
    );
    return applied ?? enabled;
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isWindows) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isPresenterFullscreen') ?? false;
  }
}
