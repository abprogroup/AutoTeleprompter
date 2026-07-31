import 'dart:async';

import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';
import '../../features/teleprompter/services/native_speech_service.dart';

/// Android STT adapter.
///
/// Wraps [SpeechService] (speech_to_text plugin, Google SpeechRecognizer)
/// as the primary path. Some OEMs (ColorOS/MIUI/OneUI) restrict Google's
/// speech-recognition-hosting app to foreground-only microphone access,
/// which makes the plugin path fail immediately with error_permission even
/// though this app's own RECORD_AUDIO grant is fine. When that happens,
/// transparently fall back to [NativeSpeechService] (on-device
/// SpeechRecognizer, API 31+), which runs recognition in-process using this
/// app's own permission and bypasses that OEM restriction entirely.
class SttAndroidAdapter extends AbstractSttService {
  final SpeechService _inner = SpeechService();
  final NativeSpeechService _native = NativeSpeechService();
  bool _usingNative = false;
  bool _fallbackInFlight = false;
  bool _nativeFallbackAttempted = false;
  String? _pendingLocale;

  SttAndroidAdapter() {
    _inner.onResult = (r) {
      if (!_usingNative) onResult?.call(r);
    };
    _inner.onStatusChange = (s) {
      if (_usingNative || _fallbackInFlight) return;
      onStatusChange?.call(s);
    };
    _inner.onError = (e) => _handlePluginError(e);
    _inner.onLanguageUnavailable = (locale) {
      if (!_usingNative) onLanguageUnavailable?.call(locale);
    };

    _native.onResult = (r) {
      if (_usingNative) onResult?.call(r);
    };
    _native.onStatusChange = (s) {
      if (_usingNative) onStatusChange?.call(s);
    };
    _native.onError = (e) {
      if (_usingNative) onError?.call(e);
    };
    _native.onLanguageUnavailable = (locale) {
      if (_usingNative) onLanguageUnavailable?.call(locale);
    };
  }

  void _handlePluginError(String error) {
    if (_usingNative) return;
    // error_permission/error_audio/error_insufficient_permissions is the
    // classic OEM mic-block signature, but on ColorOS the same restriction
    // has also been observed surfacing as error_unknown/error_client — the
    // plugin briefly reports "listening" then aborts within ~1s with no
    // permission-flavored code at all. Only attempt the fallback once per
    // session so the plugin's own retry loop isn't fought if the native path
    // also can't help.
    final looksLikeOemBlock = error == 'error_permission' ||
        error == 'error_audio' ||
        error == 'error_insufficient_permissions' ||
        error == 'error_unknown' ||
        error == 'error_client';
    if (looksLikeOemBlock && !_fallbackInFlight && !_nativeFallbackAttempted) {
      _fallbackInFlight = true;
      _nativeFallbackAttempted = true;
      onDiagnostic?.call(
          '[STT] Standard recognizer failed ($error) - trying on-device fallback...');
      unawaited(_tryNativeFallback());
      return;
    }
    if (!_fallbackInFlight) onError?.call(error);
  }

  /// Called once the standard plugin path has failed in a way that matches
  /// the known OEM mic-block signature. Tries the in-process on-device
  /// recognizer instead of giving up.
  Future<void> _tryNativeFallback() async {
    final availability = await NativeSpeechService.checkAvailability();
    if (availability['available'] != true) {
      _fallbackInFlight = false;
      onDiagnostic?.call(
          '[STT] On-device fallback unavailable on this device (API ${availability['apiLevel']}).');
      onError?.call('error_permission');
      onStatusChange?.call(SpeechStatus.error);
      return;
    }
    final result = await _native.start(localeId: _pendingLocale);
    _fallbackInFlight = false;
    if (result.success) {
      _usingNative = true;
      onDiagnostic?.call('[STT] On-device fallback active.');
    } else {
      onDiagnostic?.call('[STT] On-device fallback failed: ${result.message}');
      onError?.call('error_permission');
      onStatusChange?.call(SpeechStatus.error);
    }
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) {
    _pendingLocale = localeId;
    _usingNative = false;
    _fallbackInFlight = false;
    _nativeFallbackAttempted = false;
    return _inner.start(localeId: localeId);
  }

  @override
  Future<void> stop() async {
    _fallbackInFlight = false;
    if (_usingNative) {
      _usingNative = false;
      await _native.stop();
    }
    await _inner.stop();
  }

  @override
  bool get isListening => _usingNative ? _native.isListening : _inner.isListening;

  @override
  void setLocale(String locale) {
    _pendingLocale = locale;
    if (!_usingNative) _inner.setLocale(locale);
  }

  @override
  String get platformName => 'Android';
}
