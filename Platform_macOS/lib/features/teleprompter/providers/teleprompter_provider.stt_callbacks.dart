part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttCallbacks on TeleprompterNotifier {
  void _setupWhisperCallbacks() {
    _whisperService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _whisperService.onStatusChange = (status) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('WHISPER STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _whisperService.onError = (error) {
      if (_disposed || _sessionStopped) return;
      final safeError = _sanitizeSttStatusText(error);
      _addDebugLog('WHISPER ERROR: $safeError');
      final isFatal =
          error.contains('not available') || error.contains('init failed');
      if (isFatal) {
        _safeSetState((s) => s.copyWith(
              statusMessage: safeError,
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
      }
    };
  }

  void _setupSttCallbacks() {
    final platform = _sttService.platformName;

    _sttService.onResult = (result) {
      if (_disposed || _sessionStopped) return;
      final now = DateTime.now();
      _lastVolLog = now;
      _lastSttResultAt = now;
      _pulseSpeechActivityMeterFromResult(result);
      _handleSttResult(result);
    };

    _sttService.onSoundLevelChange = (level) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final clampedLevel = _normalizeSoundLevelForMeter(level);
      final now = DateTime.now();
      if (_sttService.platformName == 'Apple') {
        _lastVolLog = now;
      }
      _safeSetState(
        (s) => s.copyWith(soundLevel: clampedLevel),
      );
      if (clampedLevel > 0.02) _lastVolLog = now;
    };

    _sttService.onDiagnostic = (msg) {
      if (_disposed) return;
      _addDebugLog(msg);
    };

    _sttService.onAudioInputDevicesChanged = (devices) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      _safeSetState((s) => s.copyWith(audioInputDevices: devices));

      final selectedId = ref.read(settingsProvider).sttInputDeviceId;
      if (selectedId.isEmpty) return;
      for (final device in devices) {
        if (device.id == selectedId) {
          final currentLabel = ref.read(settingsProvider).sttInputDeviceLabel;
          if (device.label.isNotEmpty && device.label != currentLabel) {
            ref
                .read(settingsProvider.notifier)
                .setSttInputDevice(device.id, device.label);
          }
          return;
        }
      }
      _addDebugLog(
          'Selected microphone was not found; using system default input.');
    };

    _sttService.onStatusChange = (status) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('[$platform] STATUS: $status');
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    _sttService.onError = (error) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final safeError = _sanitizeSttStatusText(error);
      _addDebugLog('[$platform] STT ERROR: $safeError');
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available') ||
          error.contains('error_unknown');
      _safeSetState((s) => s.copyWith(
            statusMessage: isFatal ? safeError : '',
            hasError: isFatal,
            isListening: isFatal ? false : s.isListening,
            isStarting: isFatal ? false : s.isStarting,
          ));
    };

    _sttService.onLanguageUnavailable = (requestedLocale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(
        _scriptLanguageLocale ?? requestedLocale,
      );
      _addDebugLog('[$platform] LANGUAGE UNAVAILABLE: $langName');
      _safeSetState((s) => s.copyWith(
            missingLanguage: langName,
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                'Speech recognition language not installed on this device',
          ));
    };

    _sttService.onNeedLanguagePack = (locale) {
      if (_useWhisper || _disposed || _sessionStopped) return;
      final langName = SpeechStartResult.languageNameFromLocale(locale);
      _addDebugLog(
          '[$platform] ALL STT FAILED for $langName - internet required');
      _safeSetState((s) => s.copyWith(
            hasError: true,
            isListening: false,
            isStarting: false,
            statusMessage:
                '$langName speech recognition requires an internet connection. '
                'This language is not available offline on your device. '
                'Please connect to WiFi or mobile data and try again.',
          ));
    };
  }

  String _sanitizeSttStatusText(Object error) {
    var sanitized = error.toString();
    sanitized = sanitized.replaceAll(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer <redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'([?&](?:pin|token|access_token|refresh_token|client_secret|password)=)'
        r'[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'''(["']?(?:access_token|refresh_token|client_secret|password|apikey|api_key|authorization|pin|token)["']?\s*[:=]\s*)["']?[^"',}&\s]+''',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'(/Users/|/private/var/|/var/folders/)[^\s,;)\]}]+'),
      '<local-path>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'[A-Z]:\\Users\\[^ \t\r\n,;)\]}]+', caseSensitive: false),
      '<local-path>',
    );
    return sanitized.length <= 280
        ? sanitized
        : '${sanitized.substring(0, 280)}...';
  }

  double _normalizeSoundLevelForMeter(double rawLevel) {
    if (rawLevel.isNaN || rawLevel.isInfinite) return 0.0;
    if (rawLevel >= 0.0 && rawLevel <= 1.0) {
      return rawLevel.clamp(0.0, 1.0).toDouble();
    }

    // speech_to_text reports platform-native level units. Depending on the
    // backend this can be 0-10, 0-100, or a negative dB-like value.
    if (rawLevel > 1.0 && rawLevel <= 10.0) {
      return (rawLevel / 10.0).clamp(0.0, 1.0).toDouble();
    }
    if (rawLevel > 10.0 && rawLevel <= 100.0) {
      return (rawLevel / 100.0).clamp(0.0, 1.0).toDouble();
    }
    if (rawLevel < 0.0) {
      return ((rawLevel + 60.0) / 60.0).clamp(0.0, 1.0).toDouble();
    }
    return 1.0;
  }

  void _pulseSpeechActivityMeterFromResult(SpeechResult result) {
    if (_useWhisper ||
        _disposed ||
        _sessionStopped ||
        _sttService.platformName != 'Apple' ||
        result.words.trim().isEmpty) {
      return;
    }

    final token = ++_speechActivityMeterToken;
    _speechActivityMeterTimer?.cancel();
    final peak = result.isFinal ? 0.52 : 0.82;
    _safeSetState((s) => s.copyWith(soundLevel: peak));
    _speechActivityMeterTimer = Timer(const Duration(milliseconds: 260), () {
      if (_disposed || _sessionStopped || token != _speechActivityMeterToken) {
        return;
      }
      final recent = _lastSttResultAt != null &&
          DateTime.now().difference(_lastSttResultAt!) <
              const Duration(milliseconds: 420);
      _safeSetState((s) => s.copyWith(soundLevel: recent ? 0.12 : 0.0));
    });
  }
}
