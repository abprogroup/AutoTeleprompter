import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';
import '../../features/teleprompter/services/native_speech_service.dart';

/// Android STT adapter.
///
/// Wraps [NativeSpeechService] which uses Android's
/// SpeechRecognizer.createOnDeviceSpeechRecognizer() (API 31+) via a
/// platform channel. This bypasses ColorOS/MIUI/OneUI restrictions that
/// block the standard speech_to_text plugin from accessing the microphone.
class SttAndroidAdapter extends AbstractSttService {
  final NativeSpeechService _inner = NativeSpeechService();

  SttAndroidAdapter() {
    // Wire inner callbacks to forward through to outer callbacks.
    // Lambdas capture `this` so outer callbacks set after construction
    // are still reached correctly at call time.
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
    _inner.onSoundLevelChange = (l) => onSoundLevelChange?.call(l);
    _inner.onLanguageUnavailable = (l) => onLanguageUnavailable?.call(l);
    _inner.onNeedLanguagePack = (l) => onNeedLanguagePack?.call(l);
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) =>
      _inner.start(localeId: localeId);

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Android';

  @override
  bool get requiresImmediateListeningFlag => false;
}
