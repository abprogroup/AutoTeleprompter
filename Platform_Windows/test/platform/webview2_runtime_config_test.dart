import 'dart:io';

import 'package:autoteleprompter/platform/webview2/webview2_runtime_config.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test('rejects non-local speech bridge urls', () {
    expect(WebView2RuntimeConfig.configureForLocalSttUrl(null), isFalse);
    expect(WebView2RuntimeConfig.configureForLocalSttUrl(''), isFalse);
    expect(
      WebView2RuntimeConfig.configureForLocalSttUrl(
        'https://localhost:8082/?session=1',
      ),
      isFalse,
    );
    expect(
      WebView2RuntimeConfig.configureForLocalSttUrl(
        'http://127.0.0.1:8082/?session=1',
      ),
      isFalse,
    );
  });

  test('configures WebView2 microphone flags in the current process only',
      () async {
    if (!Platform.isWindows) {
      expect(
        WebView2RuntimeConfig.configureForLocalSttUrl(
          'http://localhost:18082/?session=1',
        ),
        isFalse,
      );
      return;
    }
    final previousArguments = _currentProcessWebView2Arguments();
    addTearDown(() => _setCurrentProcessWebView2Arguments(previousArguments));

    expect(
      WebView2RuntimeConfig.configureForLocalSttUrl(
        'http://localhost:18082/?session=1',
      ),
      isTrue,
    );

    final output = _currentProcessWebView2Arguments();

    expect(output, contains('--use-fake-ui-for-media-stream'));
    expect(
      output,
      contains(
        '--unsafely-treat-insecure-origin-as-secure=http://localhost:18082',
      ),
    );
    expect(output, contains('--autoplay-policy=no-user-gesture-required'));
  });
}

String _currentProcessWebView2Arguments() {
  const key = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
  final keyPtr = key.toNativeUtf16();
  final buffer = calloc.allocate<Utf16>(4096);
  try {
    final length = GetEnvironmentVariable(keyPtr, buffer, 4096);
    if (length == 0) return '';
    return buffer.toDartString(length: length);
  } finally {
    calloc
      ..free(keyPtr)
      ..free(buffer);
  }
}

void _setCurrentProcessWebView2Arguments(String value) {
  const key = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';
  final keyPtr = key.toNativeUtf16();
  final valuePtr = value.toNativeUtf16();
  try {
    SetEnvironmentVariable(keyPtr, valuePtr);
  } finally {
    calloc
      ..free(keyPtr)
      ..free(valuePtr);
  }
}
