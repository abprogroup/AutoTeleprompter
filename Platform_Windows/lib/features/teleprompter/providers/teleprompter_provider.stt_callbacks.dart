part of 'teleprompter_provider.dart';

String _normalizeSttInputLabel(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

bool _hasUniqueSttInputLabelMatch(
  List<SttAudioInputDevice> devices,
  String selectedLabel,
) {
  final wanted = _normalizeSttInputLabel(selectedLabel);
  if (wanted.isEmpty || wanted == 'system default microphone') return false;

  final exact =
      devices
          .where((device) => _normalizeSttInputLabel(device.label) == wanted)
          .length;
  if (exact == 1) return true;

  if (wanted.length < 8) return false;
  final partial =
      devices.where((device) {
        final candidate = _normalizeSttInputLabel(device.label);
        return candidate.length >= 8 &&
            (candidate.contains(wanted) || wanted.contains(candidate));
      }).length;
  return partial == 1;
}

extension TeleprompterSttCallbacks on TeleprompterNotifier {
  void _setupSttCallbacks(AbstractSttService service) {
    final platform = service.platformName;

    service.onResult = (result) {
      if (_disposed ||
          _sessionStopped ||
          _sttHostTransitionInFlight ||
          service != _sttService) {
        return;
      }
      _handleSttResult(result);
    };

    service.onSoundLevelChange = (level) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          _sttHostTransitionInFlight ||
          service != _sttService) {
        return;
      }
      final clamped = level.clamp(0.0, 1.0).toDouble();
      if ((_currentState.soundLevel - clamped).abs() < 0.005) return;
      _safeSetState((s) => s.copyWith(soundLevel: clamped));
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

      final settings = ref.read(settingsProvider);
      final selectedId = settings.sttInputDeviceId;
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
      if ((_useExternalEdgeSttHost || _useExternalChromeSttHost) &&
          _hasUniqueSttInputLabelMatch(devices, settings.sttInputDeviceLabel)) {
        // Device IDs are browser-profile scoped. The page remaps this label to
        // the external host's ID without replacing the embedded host setting.
        return;
      }
      _addDebugLog(
        'Selected microphone was not found; using system default input.',
      );
    };

    service.onRuntimeHealth = (health) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      _handleBrowserHostRuntimeHealth(health);
    };

    service.onStatusChange = (status) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          service != _sttService) {
        return;
      }
      if (_sttHostTransitionInFlight && status != SpeechStatus.listening) {
        return;
      }
      if (_startingSession && status != SpeechStatus.listening) return;
      _startingSession = false;
      final debugStatus =
          status == SpeechStatus.listening
              ? 'ENGINE READY (speech not implied)'
              : status.name.toUpperCase();
      _addDebugLog('[${service.platformName}] STATUS: $debugStatus');
      LightweightDiagnostics.instance.record(
        'stt',
        'status changed',
        data: {'platform': service.platformName, 'status': '$status'},
      );
      _safeSetState(
        (s) => s.copyWith(
          isListening: status == SpeechStatus.listening,
          isStarting: false,
          statusMessage: '',
          hasError: false,
        ),
      );
    };

    service.onError = (error) {
      if (_useWhisper ||
          _disposed ||
          _sessionStopped ||
          _sttHostTransitionInFlight ||
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
      final isFatal =
          error.contains('error_audio') ||
          error.contains('error_permission') ||
          error.contains('not available') ||
          error.contains('Microphone blocked');
      _safeSetState(
        (s) => s.copyWith(
          statusMessage: isFatal ? error : '',
          hasError: isFatal,
          isListening: isFatal ? false : s.isListening,
          isStarting: isFatal ? false : s.isStarting,
        ),
      );
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
      _safeSetState(
        (s) => s.copyWith(
          missingLanguage: langName,
          hasError: true,
          isListening: false,
          isStarting: false,
          statusMessage:
              'Speech recognition language not installed on this device',
        ),
      );
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
        '[$platform] ALL STT FAILED for $langName - internet required',
      );
      _safeSetState(
        (s) => s.copyWith(
          hasError: true,
          isListening: false,
          isStarting: false,
          statusMessage:
              '$langName speech recognition requires an internet connection. '
              'This language is not available offline on your device. '
              'Please connect this Windows device to the internet and try again.',
        ),
      );
    };
  }

  void _setupWhisperCallbacks() {
    _whisperService.onResult = (result) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _handleSttResult(result);
    };

    _whisperService.onSoundLevelChange = (level) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      final clamped = level.clamp(0.0, 1.0).toDouble();
      final mustClearVisibleMeter =
          clamped == 0.0 && _currentState.soundLevel != 0.0;
      if (!mustClearVisibleMeter &&
          (_currentState.soundLevel - clamped).abs() < 0.005) {
        return;
      }
      _safeSetState((s) => s.copyWith(soundLevel: clamped));
    };

    _whisperService.onDiagnostic = (message) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('WHISPER INPUT: $message');
    };

    _whisperService.onStatusChange = (status) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      final debugStatus =
          status == SpeechStatus.listening
              ? 'ENGINE READY (speech not implied)'
              : status.name.toUpperCase();
      final isError = status == SpeechStatus.error;
      _addDebugLog('WHISPER STATUS: $debugStatus');
      _safeSetState(
        (s) => s.copyWith(
          isListening: status == SpeechStatus.listening,
          isStarting: false,
          statusMessage: isError ? s.statusMessage : '',
          hasError: isError,
          soundLevel: status == SpeechStatus.listening ? s.soundLevel : 0.0,
        ),
      );
    };

    _whisperService.onError = (error) {
      if (!_useWhisper || _disposed || _sessionStopped) return;
      _addDebugLog('WHISPER ERROR: $error');
      _safeSetState(
        (s) => s.copyWith(
          statusMessage: error,
          hasError: true,
          isListening: false,
          isStarting: false,
          soundLevel: 0.0,
        ),
      );
    };
  }
}
