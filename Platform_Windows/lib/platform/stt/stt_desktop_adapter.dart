import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Desktop STT adapter — used on Windows (and Linux if added in future).
///
/// Wraps [SpeechService] which uses the speech_to_text plugin.
/// The speech_to_text plugin supports Windows via the Windows Speech
/// Recognition API (SAPI / Windows.Media.SpeechRecognition).
///
/// Note: Windows STT requires the Windows Speech Recognition feature to
/// be enabled in Windows Settings → Time & Language → Speech.
class SttDesktopAdapter extends AbstractSttService {
  final SpeechService _inner = SpeechService();

  SttDesktopAdapter() {
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
    _inner.onSoundLevelChange = (l) => onSoundLevelChange?.call(l);
    _inner.onLanguageUnavailable = (l) => onLanguageUnavailable?.call(l);
    // onNeedLanguagePack: not applicable on Windows
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) =>
      _inner.start(localeId: localeId);

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Windows';

  @override
  bool get requiresImmediateListeningFlag => false;
}
