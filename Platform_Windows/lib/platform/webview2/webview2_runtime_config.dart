import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WebView2RuntimeConfig {
  static const _envKey = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
  static String? _lastArguments;

  static bool configureForLocalSttUrl(String? url) {
    if (!Platform.isWindows || url == null || url.trim().isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'http' || uri.host != 'localhost') {
      return false;
    }

    final origin = 'http://localhost:${uri.port}';
    final arguments = [
      '--use-fake-ui-for-media-stream',
      '--unsafely-treat-insecure-origin-as-secure=$origin',
      '--autoplay-policy=no-user-gesture-required',
    ].join(' ');

    if (_lastArguments == arguments) return true;

    final key = _envKey.toNativeUtf16();
    final value = arguments.toNativeUtf16();
    try {
      final ok = SetEnvironmentVariable(key, value) != 0;
      if (ok) _lastArguments = arguments;
      return ok;
    } finally {
      calloc.free(key);
      calloc.free(value);
    }
  }
}
