import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridges to the native Android clipboard via MethodChannel to place
/// both plain-text and HTML flavours on the clipboard. Falls back to the
/// Flutter plain-text clipboard on any failure or unsupported platform.
class RichClipboard {
  static const MethodChannel _channel =
      MethodChannel('autoteleprompter/clipboard');

  static String? _internalMarkup;

  static Future<void> setHtml({
    required String plain,
    required String html,
    String? markup,
  }) async {
    _internalMarkup = markup;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final ok = await _channel.invokeMethod<bool>('setHtml', {
          'plain': plain,
          'html': html,
        });
        if (ok == true) return;
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('RichClipboard HTML fallback: $error\n$stackTrace');
      }
      // fall through to plain-text fallback
    }
    await Clipboard.setData(ClipboardData(text: plain));
  }

  static String? get internalMarkup => _internalMarkup;

  /// Clears the internal markup buffer so stale rich styles cannot leak
  /// into a paste after the OS clipboard has been replaced externally.
  static void clearInternal() => _internalMarkup = null;
}
