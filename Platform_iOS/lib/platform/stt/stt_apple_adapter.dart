import 'abstract_stt_service.dart';
import 'ios_audio_input_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Apple STT adapter — used on iOS and macOS.
///
/// Wraps [SpeechService] which uses Apple's SFSpeechRecognizer via the
/// speech_to_text plugin. Both iOS and macOS share the same implementation
/// because they both use the Apple Speech framework.
///
/// Key difference from Android: Apple's status callbacks fire asynchronously
/// after start() returns. [requiresImmediateListeningFlag] is therefore true,
/// so the caller sets isListening=true immediately rather than waiting.
class SttAppleAdapter extends AbstractSttService {
  final SpeechService _inner = SpeechService();
  String? _selectedInputId;
  String _selectedInputLabel = 'System default microphone';

  SttAppleAdapter() {
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
    _inner.onLanguageUnavailable = (l) => onLanguageUnavailable?.call(l);
    _inner.beforeListen =
        () => setAudioInputDevice(_selectedInputId, label: _selectedInputLabel);
    // onNeedLanguagePack: Apple never fires this — left wired but unused
    // (onNeedLanguagePack stays null on this adapter)
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) async {
    await setAudioInputDevice(_selectedInputId, label: _selectedInputLabel);
    return _inner.start(localeId: localeId);
  }

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Apple';

  @override
  Future<List<SttAudioInputDevice>> refreshAudioInputDevices() async {
    try {
      final devices = await IosAudioInputService.listInputs();
      onAudioInputDevicesChanged?.call(devices);
      return devices;
    } catch (_) {
      onAudioInputDevicesChanged?.call(const []);
      return const [];
    }
  }

  @override
  Future<void> setAudioInputDevice(String? deviceId, {String? label}) async {
    final normalized = deviceId?.trim();
    _selectedInputId =
        normalized == null || normalized.isEmpty ? null : normalized;
    _selectedInputLabel = label == null || label.trim().isEmpty
        ? 'System default microphone'
        : label.trim();
    try {
      _selectedInputLabel =
          await IosAudioInputService.setPreferredInput(_selectedInputId);
      await refreshAudioInputDevices();
    } catch (_) {
      _selectedInputId = null;
      _selectedInputLabel = 'System default microphone';
      try {
        await IosAudioInputService.setPreferredInput(null);
        await refreshAudioInputDevices();
      } catch (_) {}
    }
  }

  @override
  bool get requiresImmediateListeningFlag => true;

  @override
  void setLocale(String locale) => _inner.setLocale(locale);
}
