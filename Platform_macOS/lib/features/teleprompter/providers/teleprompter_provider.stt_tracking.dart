part of 'teleprompter_provider.dart';

extension TeleprompterNotifierSttTracking on TeleprompterNotifier {
  void _resetSttTrackingState() {
    _sttEvidenceTrackingState = SttEvidenceTrackingState.locked;
  }
}
