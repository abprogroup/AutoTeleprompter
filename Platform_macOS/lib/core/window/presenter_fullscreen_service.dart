import 'dart:io';

import 'package:flutter/services.dart';

/// Toggles real OS fullscreen for the presenter, mirroring the Windows service
/// API so shared presenter/content-creator callers work unchanged. On macOS the
/// native side calls `NSWindow.toggleFullScreen` (see macos/Runner/
/// MainFlutterWindow.swift); other platforms are no-ops.
class PresenterFullscreenService {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/window');

  static Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isMacOS) {
      return enabled;
    }
    final applied = await _channel.invokeMethod<bool>(
      'setPresenterFullscreen',
      enabled,
    );
    return applied ?? enabled;
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isMacOS) {
      return false;
    }
    return await _channel.invokeMethod<bool>('isPresenterFullscreen') ?? false;
  }
}
