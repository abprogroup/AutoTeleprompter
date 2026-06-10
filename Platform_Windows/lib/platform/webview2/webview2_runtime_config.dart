import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WebView2RuntimeConfig {
  static const int _defaultSttPort = 8082;
  static const int _maxFallbackSttPort = 8092;
  static const _envKey = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
  static String? _lastArguments;

  static bool configureForLocalSttDefaults() {
    if (!Platform.isWindows) return false;
    return _setArguments(_buildArguments(_localSttOrigins()));
  }

  static bool configureForLocalSttUrl(String? url) {
    if (!Platform.isWindows || url == null || url.trim().isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'http' || uri.host != 'localhost') {
      return false;
    }

    final origins = {
      ..._localSttOrigins(),
      'http://localhost:${uri.port}',
    };
    return _setArguments(_buildArguments(origins));
  }

  static List<String> _localSttOrigins() => [
        for (var port = _defaultSttPort; port <= _maxFallbackSttPort; port++)
          'http://localhost:$port',
      ];

  static String _buildArguments(Iterable<String> secureOrigins) {
    final origins = secureOrigins.where((origin) => origin.trim().isNotEmpty);
    return [
      '--use-fake-ui-for-media-stream',
      '--unsafely-treat-insecure-origin-as-secure=${origins.join(',')}',
      '--autoplay-policy=no-user-gesture-required',
    ].join(' ');
  }

  static bool _setArguments(String arguments) {
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
