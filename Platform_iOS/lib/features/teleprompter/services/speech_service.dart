import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

enum SpeechStatus { idle, listening, paused, error }

class SpeechResult {
  final String words;
  final bool isFinal;
  SpeechResult(this.words, this.isFinal);
}

/// Result of starting the speech service — tells the caller what happened.
class SpeechStartResult {
  final bool success;
  final String? actualLocale; // The locale that was actually used
  final String? requestedLocale; // What was requested
  final bool languageMissing; // True if requested language wasn't available
  final String?
      missingLanguageName; // Human-readable name of the missing language
  final String? message;

  SpeechStartResult({
    required this.success,
    this.actualLocale,
    this.requestedLocale,
    this.languageMissing = false,
    this.missingLanguageName,
    this.message,
  });

  /// Map common locale prefixes to human-readable language names
  static String languageNameFromLocale(String localeId) {
    final lang = localeId.toLowerCase().split(RegExp(r'[_-]')).first;
    const names = {
      'he': 'Hebrew',
      'en': 'English',
      'ar': 'Arabic',
      'fr': 'French',
      'de': 'German',
      'es': 'Spanish',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'hi': 'Hindi',
      'tr': 'Turkish',
      'pl': 'Polish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'da': 'Danish',
      'fi': 'Finnish',
      'no': 'Norwegian',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'uk': 'Ukrainian',
      'cs': 'Czech',
      'ro': 'Romanian',
      'hu': 'Hungarian',
      'el': 'Greek',
      'id': 'Indonesian',
      'ms': 'Malay',
      'fa': 'Persian',
      'bn': 'Bengali',
      'ta': 'Tamil',
    };
    return names[lang] ?? localeId;
  }
}

/// Speech-to-text service wrapper for iOS speech recognition.
///
/// Handles known quirks:
/// - Apple speech callbacks can arrive after start/stop state changes
/// - Some languages require a network connection on-device
/// - Locale identifiers can vary by device (en_US vs en-US vs en_GB)
class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _isActive = false;
  bool _isInitialized = false;
  bool _isRestarting = false;
  String _localeId = 'en_US';
  int _languageRetries = 0; // Prevent infinite language error loop

  int _consecutiveErrors = 0;
  Timer? _errorResetTimer;

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;
  void Function(double level)? onSoundLevelChange;
  Future<void> Function()? beforeListen;

  /// Fires when the language is confirmed unavailable (after retries exhausted).
  /// The string is the original requested locale ID.
  void Function(String requestedLocale)? onLanguageUnavailable;

  Future<bool> initialize() async {
    try {
      _isInitialized = await _stt.initialize(
        onError: (error) {
          if (!_isActive) return;

          final msg = error.errorMsg;
          onError?.call(msg);

          // Language error — try fallback, then give up and notify
          if (msg.contains('error_language')) {
            _languageRetries++;
            if (_languageRetries == 1 && _localeId.isNotEmpty) {
              // 1st retry: try with no locale (device default)
              _localeId = '';
              if (!_isRestarting) {
                _scheduleRestart(const Duration(milliseconds: 300));
              }
            } else if (_languageRetries == 2) {
              // 2nd retry: reset locale again and force one more try.
              _localeId = '';
              if (!_isRestarting) {
                _scheduleRestart(const Duration(milliseconds: 500));
              }
            } else {
              // Exhausted all retries — notify the UI
              _isActive = false;
              onLanguageUnavailable?.call(_localeId);
              onStatusChange?.call(SpeechStatus.error);
            }
            return;
          }

          // Permission and hardware errors — stop and notify user
          final fatal = msg == 'error_audio' ||
              msg == 'error_insufficient_permissions' ||
              msg == 'error_permission';
          if (fatal) {
            _isActive = false;
            onStatusChange?.call(SpeechStatus.error);
            return;
          }

          // Track consecutive errors
          _consecutiveErrors++;
          _errorResetTimer?.cancel();
          _errorResetTimer =
              Timer(const Duration(seconds: 10), () => _consecutiveErrors = 0);

          if (_isRestarting) return;

          final isTimeout = msg == 'error_no_match' ||
              msg.contains('no_match') ||
              msg.contains('speech_timeout');

          if (_consecutiveErrors >= 8) {
            _consecutiveErrors = 0;
            _isInitialized = false;
            _scheduleRestart(const Duration(milliseconds: 1200), reinit: true);
          } else if (_consecutiveErrors >= 4) {
            _consecutiveErrors = 0;
            _isInitialized = false;
            _scheduleRestart(const Duration(milliseconds: 600), reinit: true);
          } else {
            final delay = isTimeout
                ? const Duration(milliseconds: 20)
                : const Duration(milliseconds: 150);
            _scheduleRestart(delay);
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (_isActive && !_isRestarting) {
              _scheduleRestart(const Duration(milliseconds: 150));
            } else if (!_isActive) {
              onStatusChange?.call(SpeechStatus.idle);
            }
          } else if (status == 'listening') {
            onStatusChange?.call(SpeechStatus.listening);
          }
        },
        debugLogging: kDebugMode,
        options: [
          SpeechToText.androidNoBluetooth,
        ],
      );
    } catch (e) {
      onError?.call('STT init failed: $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  void _scheduleRestart(Duration delay, {bool reinit = false}) {
    if (_isRestarting) return;
    _isRestarting = true;
    Future.delayed(delay, () async {
      _isRestarting = false;
      if (!_isActive) return;
      if (reinit) {
        await initialize();
      }
      if (_isActive) await _startListening();
    });
  }

  /// Find the best matching locale from the device's available locales.
  /// Returns null if the requested language isn't available at all.
  String? _findBestLocale(List<LocaleName> locales, String requestedId) {
    if (locales.isEmpty) return null;

    // Normalize: both underscore and hyphen formats (en_US, en-US)
    final normalized = requestedId.toLowerCase().replaceAll('-', '_');
    final lang = normalized.split('_').first;

    // 1. Exact match
    for (final l in locales) {
      if (l.localeId.toLowerCase().replaceAll('-', '_') == normalized) {
        return l.localeId;
      }
    }

    // 2. Language match (e.g. requested en_US, found en_GB)
    for (final l in locales) {
      if (l.localeId
          .toLowerCase()
          .replaceAll('-', '_')
          .startsWith('${lang}_')) {
        return l.localeId;
      }
    }

    // 3. Bare language match (some devices list just 'en' not 'en_US')
    for (final l in locales) {
      if (l.localeId.toLowerCase() == lang) {
        return l.localeId;
      }
    }

    return null;
  }

  /// Start speech recognition. Returns a [SpeechStartResult] so the caller
  /// knows if the requested language was available or if a fallback was used.
  Future<SpeechStartResult> start({String? localeId}) async {
    final hasPermission = await _stt.hasPermission;

    if (!_isInitialized || !hasPermission) {
      final ok = await initialize();
      if (!ok) {
        return SpeechStartResult(
          success: false,
          message:
              'Speech recognition is not available. Check iOS Speech Recognition and Microphone permissions for AutoTeleprompter.',
        );
      }
    }

    // Get available locales from the device
    final locales = await _stt.locales();
    bool languageMissing = false;
    String? requestedLang = localeId;

    if (localeId != null && localeId.isNotEmpty) {
      final bestMatch = _findBestLocale(locales, localeId);
      if (bestMatch != null) {
        _localeId = bestMatch;
      } else {
        // Requested language not available — fall back but flag it
        languageMissing = true;
        _localeId = '';
      }
    } else {
      // No locale specified — use device default
      _localeId = '';
    }

    _isActive = true;
    _consecutiveErrors = 0;
    _languageRetries = 0;
    _isRestarting = false;
    await _startListening();

    return SpeechStartResult(
      success: true,
      actualLocale: _localeId.isEmpty ? 'device default' : _localeId,
      requestedLocale: requestedLang,
      languageMissing: languageMissing,
      missingLanguageName: languageMissing && requestedLang != null
          ? SpeechStartResult.languageNameFromLocale(requestedLang)
          : null,
    );
  }

  Future<void> _startListening() async {
    if (!_isActive) return;
    try {
      if (_stt.isListening) {
        await _stt.cancel();
        await Future.delayed(const Duration(milliseconds: 80));
      }
      // Use the simplest possible listen call — no locale override,
      // no special modes. Let the device's speech recognizer decide everything.
      // Only specify locale if explicitly set (non-empty).
      final useLocale = _localeId.isEmpty ? null : _localeId;
      await beforeListen?.call();
      await _stt.listen(
        onResult: (SpeechRecognitionResult result) {
          _consecutiveErrors = 0;
          if (result.recognizedWords.isNotEmpty) {
            onResult?.call(
                SpeechResult(result.recognizedWords, result.finalResult));
          }
          if (result.finalResult && _isActive && !_isRestarting) {
            _scheduleRestart(const Duration(milliseconds: 100));
          }
        },
        onSoundLevelChange: (level) => onSoundLevelChange?.call(level),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          localeId: useLocale,
          // Cap each session so the cumulative transcript stays short and the
          // recognizer recycles quickly (lower latency, smaller debug output).
          // The restart loop keeps recognition effectively continuous.
          listenFor: const Duration(seconds: 8),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      onError?.call('Listen failed: $e');
      if (_isActive && !_isRestarting) {
        _isInitialized = false;
        _scheduleRestart(const Duration(milliseconds: 600), reinit: true);
      }
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _isRestarting = false;
    _consecutiveErrors = 0;
    _errorResetTimer?.cancel();
    await _stt.stop();
    onStatusChange?.call(SpeechStatus.idle);
  }

  Future<void> pause() async {
    _isActive = false;
    _isRestarting = false;
    _errorResetTimer?.cancel();
    await _stt.stop();
    onStatusChange?.call(SpeechStatus.paused);
  }

  bool get isListening => _stt.isListening;

  /// Switch locale without stopping — new locale takes effect on next restart.
  /// Calls _stt.cancel() to trigger _scheduleRestart immediately so the switch
  /// is near-instant rather than waiting for the next utterance boundary.
  void setLocale(String locale) {
    if (locale == _localeId) return;
    _localeId = locale;
    if (_isActive && !_isRestarting && _stt.isListening) {
      _stt.cancel();
    }
  }
}
