import 'abstract_stt_service.dart';
import '../../features/teleprompter/services/speech_service.dart';

/// Android STT adapter.
///
/// Wraps [SpeechService] which uses the speech_to_text plugin
/// (Google SpeechRecognizer with 4-stage fallback chain).
class SttAndroidAdapter extends AbstractSttService {
  final SpeechService _inner = SpeechService();

  SttAndroidAdapter() {
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
  }

  @override
  Future<void> start({String? localeId}) => _inner.start(localeId: localeId);

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Android';
}
