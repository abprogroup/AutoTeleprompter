import 'dart:async';
import 'package:flutter/services.dart';
import 'speech_service.dart';

/// Native Android speech recognition service.
///
/// Uses Android's SpeechRecognizer.createOnDeviceSpeechRecognizer() on API 31+,
/// which runs in OUR app's process and uses OUR microphone permission.
/// This bypasses the issue on ColorOS/MIUI/OneUI where the Google app's
/// microphone permission is restricted to foreground-only, blocking the
/// standard speech_to_text plugin from accessing the mic.
class NativeSpeechService {
  static const _channel = MethodChannel('autoteleprompter/stt');
  bool _isActive = false;

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;
  void Function(double level)? onSoundLevelChange;
  void Function(String requestedLocale)? onLanguageUnavailable;
  /// Fires when the device needs an offline speech pack download
  /// (ColorOS/MIUI devices where regular STT mic is blocked).
  void Function(String locale)? onNeedLanguagePack;

  NativeSpeechService() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (!_isActive) return;
    switch (call.method) {
      case 'onResult':
        final data = Map<String, dynamic>.from(call.arguments as Map);
        final words = data['words'] as String? ?? '';
        final isFinal = data['isFinal'] as bool? ?? false;
        if (words.isNotEmpty) {
          onResult?.call(SpeechResult(words, isFinal));
        }
        break;
      case 'onStatus':
        final status = call.arguments as String;
        if (status == 'listening') {
          onStatusChange?.call(SpeechStatus.listening);
        } else if (status == 'error') {
          onStatusChange?.call(SpeechStatus.error);
        } else {
          onStatusChange?.call(SpeechStatus.idle);
        }
        break;
      case 'onError':
        final error = call.arguments as String;
        if (error.contains('error_language')) {
          onLanguageUnavailable?.call(error);
        }
        onError?.call(error);
        break;
      case 'onNeedLanguagePack':
        final locale = call.arguments as String? ?? 'en-US';
        onNeedLanguagePack?.call(locale);
        break;
    }
  }

  /// Check if native STT is available
  static Future<Map<String, dynamic>> checkAvailability() async {
    try {
      final result = await _channel.invokeMethod('isAvailable');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return {'available': false, 'onDevice': false, 'apiLevel': 0};
    }
  }

  /// Start speech recognition
  Future<SpeechStartResult> start({String? localeId}) async {
    _isActive = true;
    try {
      final result = await _channel.invokeMethod('start', {
        'locale': localeId,
      });
      final data = Map<String, dynamic>.from(result as Map);
      if (data['success'] == true) {
        return SpeechStartResult(
          success: true,
          actualLocale: localeId ?? 'device default',
          requestedLocale: localeId,
        );
      } else {
        _isActive = false;
        return SpeechStartResult(
          success: false,
          message: data['message'] as String? ?? 'Native STT failed to start',
        );
      }
    } catch (e) {
      _isActive = false;
      return SpeechStartResult(
        success: false,
        message: 'Native STT not available: $e',
      );
    }
  }

  Future<void> stop() async {
    _isActive = false;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    onStatusChange?.call(SpeechStatus.idle);
  }

  bool get isListening => _isActive;
}
