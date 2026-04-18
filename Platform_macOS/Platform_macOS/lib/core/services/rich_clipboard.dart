import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges to the native Android clipboard via MethodChannel to place
/// both plain-text and HTML flavours on the clipboard. Falls back to the
/// Flutter plain-text clipboard on any failure or unsupported platform.
class RichClipboard {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/clipboard');

  static Future<void> setHtml({
    required String plain,
    required String html,
  }) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _channel.invokeMethod<bool>('setHtml', {
          'plain': plain,
          'html': html,
        });
        if (ok == true) return;
      }
    } catch (_) {
      // fall through to plain-text fallback
    }
    await Clipboard.setData(ClipboardData(text: plain));
  }
}
