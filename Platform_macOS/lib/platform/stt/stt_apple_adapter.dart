import 'abstract_stt_service.dart';
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

  SttAppleAdapter() {
    _inner.onResult = (r) => onResult?.call(r);
    _inner.onStatusChange = (s) => onStatusChange?.call(s);
    _inner.onError = (e) => onError?.call(e);
    _inner.onLanguageUnavailable = (l) => onLanguageUnavailable?.call(l);
    // onNeedLanguagePack: Apple never fires this — left wired but unused
    // (onNeedLanguagePack stays null on this adapter)
  }

  @override
  Future<SpeechStartResult> start({String? localeId}) =>
      _inner.start(localeId: localeId);

  @override
  Future<void> stop() => _inner.stop();

  @override
  bool get isListening => _inner.isListening;

  @override
  String get platformName => 'Apple';

  @override
  bool get requiresImmediateListeningFlag => true;
}
