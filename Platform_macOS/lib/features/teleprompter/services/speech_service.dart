import 'dart:async';
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

/// Google STT service — designed to work reliably across ALL Android devices.
///
/// Handles known quirks:
/// - Oppo/Realme/OnePlus (ColorOS): Bluetooth permission issues
/// - Xiaomi (MIUI): Intent lookup failures
/// - Samsung (One UI): Non-standard speech recognition providers
/// - Android 12+ (API 31+): BLUETOOTH_CONNECT permission requirement
/// - Various devices: Locale format differences (en_US vs en-US vs en_GB)
class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _isActive = false;
  bool _isInitialized = false;
  bool _isRestarting = false;
  String _localeId = 'en_US';
  int _languageRetries = 0; // Prevent infinite language error loop
  int _localeSwitchToken = 0;
  DateTime? _localeSwitchGraceUntil;
  Future<void> _engineQueue = Future.value();
  Timer? _restartTimer;
  DateTime? _engineRecoveryUntil;

  int _consecutiveErrors = 0;
  Timer? _errorResetTimer;

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;
  void Function(double level)? onSoundLevelChange;

  /// Fires when the language is confirmed unavailable (after retries exhausted).
  /// The string is the original requested locale ID.
  void Function(String requestedLocale)? onLanguageUnavailable;

  Future<bool> initialize() async {
    try {
      _isInitialized = await _stt.initialize(
        onError: (error) {
          if (!_isActive) return;

          final msg = error.errorMsg;
          if (_isAppleUnknownSpeechError(msg)) {
            _handleAppleUnknownSpeechError(msg);
            return;
          }
          if (_isAppleTransientRetryError(msg)) {
            onError?.call(msg);
            return;
          }

          final inLocaleSwitchGrace = _localeSwitchGraceUntil != null &&
              DateTime.now().isBefore(_localeSwitchGraceUntil!);
          if (inLocaleSwitchGrace &&
              (msg.contains('error_language') ||
                  msg.contains('no_match') ||
                  msg.contains('speech_timeout'))) {
            return;
          }
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
              // 2nd retry: try with explicit device locale in case null didn't work
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
            if (_isActive) {
              onStatusChange?.call(SpeechStatus.listening);
            }
          }
        },
        debugLogging: true,
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

  bool _isAppleUnknownSpeechError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('error_unknown') || lower.trim() == '7';
  }

  bool _isAppleTransientRetryError(String msg) {
    return msg.toLowerCase().contains('error_retry');
  }

  void _handleAppleUnknownSpeechError(String msg) {
    _isActive = false;
    _isRestarting = false;
    _isInitialized = false;
    _localeSwitchToken++;
    _consecutiveErrors = 0;
    _errorResetTimer?.cancel();
    _cancelPendingRestart();
    _engineRecoveryUntil =
        DateTime.now().add(const Duration(milliseconds: 1600));

    onError?.call(
      'Apple Speech not available right now ($msg). Wait a moment, then start STT again. '
      'If it repeats, check macOS Microphone and Speech Recognition permissions.',
    );
    onStatusChange?.call(SpeechStatus.error);

    unawaited(_runEngineOperation(() async {
      await _cancelNativeRecognition(
        settle: const Duration(milliseconds: 1200),
      );
    }));
  }

  Future<T> _runEngineOperation<T>(Future<T> Function() operation) {
    final previous = _engineQueue;
    final completer = Completer<void>();
    _engineQueue = previous.catchError((_) {}).then((_) => completer.future);

    return (() async {
      await previous.catchError((_) {});
      try {
        return await operation();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    })();
  }

  void _cancelPendingRestart() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _isRestarting = false;
  }

  Future<void> _settleAudioEngine([
    Duration duration = const Duration(milliseconds: 650),
  ]) async {
    await Future.delayed(duration);
  }

  Future<void> _cancelNativeRecognition({
    Duration settle = const Duration(milliseconds: 750),
  }) async {
    try {
      await _stt.cancel();
    } catch (_) {
      try {
        await _stt.stop();
      } catch (_) {}
    }
    await _settleAudioEngine(settle);
  }

  void _scheduleRestart(Duration delay, {bool reinit = false}) {
    if (_isRestarting) return;
    _isRestarting = true;
    _restartTimer = Timer(delay, () {
      unawaited(_runEngineOperation(() async {
        _isRestarting = false;
        _restartTimer = null;
        if (!_isActive) return;
        if (reinit) {
          await initialize();
        }
        if (_isActive) await _startListeningLocked();
      }));
    });
  }

  void setLocale(String localeId) {
    unawaited(_runEngineOperation(() => _switchLocaleLocked(localeId)));
  }

  Future<void> _switchLocaleLocked(String localeId) async {
    final normalized = localeId.replaceAll('-', '_');
    if (normalized.isEmpty) return;
    if (_localeId.toLowerCase().replaceAll('-', '_') ==
        normalized.toLowerCase()) {
      return;
    }

    _localeSwitchToken++;
    _localeSwitchGraceUntil =
        DateTime.now().add(const Duration(milliseconds: 1800));
    _languageRetries = 0;
    _consecutiveErrors = 0;
    _isRestarting = false;

    String? bestMatch;
    try {
      if (!_isInitialized) {
        await initialize();
      }
      final locales = await _stt.locales();
      bestMatch = _findBestLocale(locales, normalized);
    } catch (_) {
      bestMatch = null;
    }
    _localeId = bestMatch ?? normalized;

    if (!_isActive) return;
    try {
      await _cancelNativeRecognition();
      if (_isActive) {
        await _startListeningLocked();
      }
    } catch (e) {
      onError?.call('Locale switch failed: $e');
    }
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
  Future<SpeechStartResult> start({String? localeId}) {
    return _runEngineOperation(() => _startLocked(localeId: localeId));
  }

  Future<SpeechStartResult> _startLocked({String? localeId}) async {
    _cancelPendingRestart();
    final recoveryUntil = _engineRecoveryUntil;
    if (recoveryUntil != null) {
      final wait = recoveryUntil.difference(DateTime.now());
      if (!wait.isNegative) {
        await Future.delayed(wait);
      }
      _engineRecoveryUntil = null;
    }

    final hasPermission = await _stt.hasPermission;

    if (!_isInitialized || !hasPermission) {
      final ok = await initialize();
      if (!ok) {
        return SpeechStartResult(
          success: false,
          message:
              'Speech recognition not available. Please check that speech recognition is enabled in your device settings.',
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
    await _startListeningLocked();
    if (!_isActive) {
      return SpeechStartResult(
        success: false,
        message:
            'Apple Speech could not start cleanly. Wait a moment, then try STT again.',
      );
    }

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

  Future<void> _startListeningLocked() async {
    if (!_isActive) return;
    try {
      final listenToken = _localeSwitchToken;
      if (_stt.isListening) {
        await _cancelNativeRecognition();
      }
      // Use the simplest possible listen call — no locale override,
      // no special modes. Let the device's speech recognizer decide everything.
      // Only specify locale if explicitly set (non-empty).
      final useLocale = _localeId.isEmpty ? null : _localeId;
      await _stt.listen(
        onResult: (SpeechRecognitionResult result) {
          if (listenToken != _localeSwitchToken) return;
          _consecutiveErrors = 0;
          if (result.recognizedWords.isNotEmpty) {
            onResult?.call(
                SpeechResult(result.recognizedWords, result.finalResult));
          }
          if (result.finalResult && _isActive && !_isRestarting) {
            _scheduleRestart(const Duration(milliseconds: 100));
          }
        },
        onSoundLevelChange: (level) {
          if (listenToken != _localeSwitchToken || !_isActive) return;
          onSoundLevelChange?.call(level);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
        localeId: useLocale,
      );
    } catch (e) {
      onError?.call('Listen failed: $e');
      if (_isActive && !_isRestarting) {
        _isActive = false;
        _isInitialized = false;
        _engineRecoveryUntil =
            DateTime.now().add(const Duration(milliseconds: 1200));
        await _cancelNativeRecognition(
          settle: const Duration(milliseconds: 1200),
        );
        onStatusChange?.call(SpeechStatus.error);
      }
    }
  }

  Future<void> stop() {
    return _runEngineOperation(_stopLocked);
  }

  Future<void> _stopLocked() async {
    _isActive = false;
    _cancelPendingRestart();
    _localeSwitchToken++;
    _consecutiveErrors = 0;
    _errorResetTimer?.cancel();
    await _cancelNativeRecognition(settle: const Duration(milliseconds: 900));
    onStatusChange?.call(SpeechStatus.idle);
  }

  Future<void> pause() {
    return _runEngineOperation(_pauseLocked);
  }

  Future<void> _pauseLocked() async {
    _isActive = false;
    _cancelPendingRestart();
    _localeSwitchToken++;
    _errorResetTimer?.cancel();
    await _cancelNativeRecognition(settle: const Duration(milliseconds: 900));
    onStatusChange?.call(SpeechStatus.paused);
  }

  bool get isListening => _stt.isListening;
}
