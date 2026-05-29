part of 'teleprompter_provider.dart';

extension TeleprompterSttCallbacks on TeleprompterNotifier {
  void _setupSttCallbacks(AbstractSttService service) {
    final platform = service.platformName;

    service.onResult = (result) {
      if (_disposed || _sessionStopped || service != _sttService) return;
      _handleSttResult(result);
    };

    service.onSoundLevelChange = (level) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      _safeSetState((s) => s.copyWith(soundLevel: level.clamp(0.0, 1.0)));
      _lastVolLog = DateTime.now();
    };

    service.onDiagnostic = (msg) {
      if (_disposed || service != _sttService) return;
      _addDebugLog(msg);
    };

    service.onAudioInputDevicesChanged = (devices) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
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

    service.onRuntimeHealth = (health) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      if (health.type == 'heartbeat') {
        _lastBrowserHeartbeatAt = DateTime.now();
        if (health.failures <= 0) return;
      }
      if (health.error == 'network' || health.failures > 0) {
        _lastRecoverableSttErrorAt = DateTime.now();
        _recoverableSttErrorCount += health.failures <= 0 ? 1 : health.failures;
        _addDebugLog(
          '[${service.platformName}] health ${health.type}: '
          'failures=$_recoverableSttErrorCount age=${health.ageMs}ms',
        );
      }
    };

    service.onStatusChange = (status) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      _addDebugLog('[${service.platformName}] STATUS: $status');
      LightweightDiagnostics.instance.record(
        'stt',
        'status changed',
        data: {'platform': service.platformName, 'status': '$status'},
      );
      _safeSetState((s) => s.copyWith(
            isListening: status == SpeechStatus.listening,
            isStarting: false,
            statusMessage: '',
            hasError: false,
          ));
    };

    service.onError = (error) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      _addDebugLog('[${service.platformName}] STT ERROR: $error');
      LightweightDiagnostics.instance.record(
        'stt',
        'STT error',
        data: {'platform': service.platformName, 'error': error},
      );
      if (error.contains('error_language')) return;
      final isFatal = error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available');
      _safeSetState((s) => s.copyWith(
            statusMessage: isFatal ? error : '',
            hasError: isFatal,
            isListening: isFatal ? false : s.isListening,
            isStarting: isFatal ? false : s.isStarting,
          ));
    };

    service.onLanguageUnavailable = (requestedLocale) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
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

    service.onNeedLanguagePack = (locale) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
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
                'Please connect this Windows device to the internet and try again.',
          ));
    };
  }

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
      _addDebugLog('WHISPER ERROR: $error');
      final isFatal =
          error.contains('not available') || error.contains('init failed');
      if (isFatal) {
        _safeSetState((s) => s.copyWith(
              statusMessage: error,
              hasError: true,
              isListening: false,
              isStarting: false,
            ));
      }
    };
  }
}
