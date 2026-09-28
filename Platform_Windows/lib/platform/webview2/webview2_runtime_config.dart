import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class WebView2RuntimeConfig {
  static const int _defaultSttPort = 8082;
  static const int _maxFallbackSttPort = 8092;
  static const String _legacySpeechServiceFeature =
      'msSpeechRecognitionServiceUseCetoService';
  static const _envKey = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
  static const _loaderOverrideKeys = <String>[
    'WEBVIEW2_BROWSER_EXECUTABLE_FOLDER',
    'WEBVIEW2_USER_DATA_FOLDER',
    _envKey,
    'WEBVIEW2_RELEASE_CHANNEL_PREFERENCE',
  ];
  static String? _lastArguments;
  static bool _environmentInitialized = false;

  static String get localSttArguments => _buildArguments(_localSttOrigins());

  static bool get environmentInitialized => _environmentInitialized;

  static void markEnvironmentInitialized() {
    _environmentInitialized = true;
  }

  /// Removes inherited process-level loader overrides before the application
  /// chooses one WebView2 environment explicitly. Registry/group-policy values
  /// remain Windows-owned and are not modified.
  static bool clearInheritedLoaderOverrides() {
    if (!Platform.isWindows) return false;
    var cleared = true;
    for (final keyName in _loaderOverrideKeys) {
      final keyCleared = _clearEnvironmentVariable(keyName);
      if (keyCleared && keyName == _envKey) _lastArguments = null;
      cleared = keyCleared && cleared;
    }
    return cleared;
  }

  static bool configureForLocalSttDefaults() {
    if (!Platform.isWindows) return false;
    if (_environmentInitialized) return true;
    return _setArguments(localSttArguments);
  }

  static bool configureForLocalSttUrl(String? url) {
    if (!Platform.isWindows || url == null || url.trim().isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'http' || uri.host != 'localhost') {
      return false;
    }
    if (uri.port < _defaultSttPort || uri.port > _maxFallbackSttPort) {
      return false;
    }

    if (_environmentInitialized) {
      return true;
    }

    final origins = {..._localSttOrigins(), 'http://localhost:${uri.port}'};
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
      // V5 Hebrew tracking was qualified against Edge's established Bing
      // speech path. WebView2's later Ceto-service rollout changed recognition
      // behavior and has an active upstream regression. Keep the embedded,
      // pinned runtime on the qualified service until a later release performs
      // explicit Hebrew microphone QA against the replacement backend.
      '--disable-features=$_legacySpeechServiceFeature',
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

  static bool _clearEnvironmentVariable(String keyName) {
    final key = keyName.toNativeUtf16();
    try {
      return SetEnvironmentVariable(key, nullptr) != 0;
    } finally {
      calloc.free(key);
    }
  }
}
