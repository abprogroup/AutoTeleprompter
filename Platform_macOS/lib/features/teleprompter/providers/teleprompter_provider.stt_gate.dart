part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttGate on TeleprompterNotifier {
  void _resetSttEvidenceGate() {
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
  }
}
