import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

enum SpeechStatus { idle, listening, paused, error }

class SpeechResult {
  final String words;
  final bool isFinal;
  SpeechResult(this.words, this.isFinal);
}

class SpeechService {
  final SpeechToText _stt = SpeechToText();
  bool _isActive = false;
  bool _isInitialized = false;
  bool _isRestarting = false;
  String _localeId = 'he_IL';

  int _consecutiveErrors = 0;
  Timer? _errorResetTimer;

  void Function(SpeechResult)? onResult;
  void Function(SpeechStatus)? onStatusChange;
  void Function(String)? onError;

  Future<bool> initialize() async {
    _isInitialized = await _stt.initialize(
      onError: (error) {
        if (!_isActive) return;

        final msg = error.errorMsg;
        // error_no_match is a normal timeout during silence — don't show to user
        final isTimeout = msg == 'error_no_match' || msg.contains('no_match');
        if (!isTimeout) {
          onError?.call(msg);
        }

        // Permanent hardware/permission errors — stop completely
        final fatal = msg == 'error_audio' ||
            msg == 'error_insufficient_permissions';
        if (fatal) {
          _isActive = false;
          return;
        }

        // Track consecutive errors
        _consecutiveErrors++;
        _errorResetTimer?.cancel();
        _errorResetTimer =
            Timer(const Duration(seconds: 10), () => _consecutiveErrors = 0);

        if (_isRestarting) return;

        if (_consecutiveErrors >= 5) {
          // Many errors — full re-init
          _consecutiveErrors = 0;
          _isInitialized = false;
          _scheduleRestart(const Duration(milliseconds: 800), reinit: true);
        } else {
          // Instant restart for silence/timeouts
          final delay = isTimeout
              ? const Duration(milliseconds: 20)
              : const Duration(milliseconds: 100); 
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
    );
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

  Future<List<LocaleName>> getAvailableLocales() async {
    if (!_isInitialized) await initialize();
    return _stt.locales();
  }

  Future<void> start({String? localeId}) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        onError?.call('Speech recognition not available on this device.');
        return;
      }
    }

    if (localeId != null) {
      _localeId = localeId;
    } else {
      // Auto: try Hebrew first, fall back to device default
      final locales = await _stt.locales();
      final hebrewLocale = locales.firstWhere(
        (l) => l.localeId.startsWith('he'),
        orElse: () =>
            locales.isNotEmpty ? locales.first : LocaleName('en_US', 'English'),
      );
      _localeId = hebrewLocale.localeId;
    }

    _isActive = true;
    _consecutiveErrors = 0;
    _isRestarting = false;
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_isActive) return;
    try {
      // Cancel any existing session cleanly before starting a new one
      if (_stt.isListening) {
        await _stt.cancel();
        await Future.delayed(const Duration(milliseconds: 80));
      }
      await _stt.listen(
        onResult: (SpeechRecognitionResult result) {
          _consecutiveErrors = 0; // actual result proves session is healthy
          if (result.recognizedWords.isNotEmpty) {
            onResult?.call(SpeechResult(result.recognizedWords, result.finalResult));
          }
          // On final result, restart immediately to continue past the time limit
          if (result.finalResult && _isActive && !_isRestarting) {
            _scheduleRestart(const Duration(milliseconds: 100));
          }
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
        localeId: _localeId,
      );
    } catch (e) {
      onError?.call('Listen failed: $e');
      // Attempt recovery
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
}
