import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Desktop STT adapter used only as a non-Apple fallback.
///
/// Wraps [SpeechService] which uses the speech_to_text plugin.
class SttDesktopAdapter extends AbstractSttService {
  final SpeechService _inner = SpeechService();

  SttDesktopAdapter() {
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
    _inner.onLanguageUnavailable = (l) => onLanguageUnavailable?.call(l);
    // onNeedLanguagePack: not applicable for this fallback adapter.
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) =>
      _inner.start(localeId: localeId);

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Desktop';

  @override
  bool get requiresImmediateListeningFlag => false;
}
