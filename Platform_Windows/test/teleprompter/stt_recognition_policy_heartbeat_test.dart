import 'package:autoteleprompter/features/teleprompter/services/stt_recognition_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('heartbeat listening readiness', () {
    test('blocks an active browser adapter before recognizer readiness', () {
      expect(
        SttRecognitionPolicyService.heartbeatListeningState(
          serviceListening: true,
          browserServiceActive: true,
          browserHostReadinessComplete: false,
          browserHostTransitionInFlight: false,
        ),
        isFalse,
      );
    });

    test('allows browser heartbeat checks only after the full handshake', () {
      expect(
        SttRecognitionPolicyService.heartbeatListeningState(
          serviceListening: true,
          browserServiceActive: true,
          browserHostReadinessComplete: true,
          browserHostTransitionInFlight: false,
        ),
        isTrue,
      );
    });

    test('blocks browser checks while the ready host is transitioning', () {
      expect(
        SttRecognitionPolicyService.heartbeatListeningState(
          serviceListening: true,
          browserServiceActive: true,
          browserHostReadinessComplete: true,
          browserHostTransitionInFlight: true,
        ),
        isFalse,
      );
    });

    test('does not gate a ready non-browser speech service', () {
      expect(
        SttRecognitionPolicyService.heartbeatListeningState(
          serviceListening: true,
          browserServiceActive: false,
          browserHostReadinessComplete: false,
          browserHostTransitionInFlight: false,
        ),
        isTrue,
      );
      expect(
        SttRecognitionPolicyService.heartbeatListeningState(
          serviceListening: false,
          browserServiceActive: false,
          browserHostReadinessComplete: true,
          browserHostTransitionInFlight: false,
        ),
        isFalse,
      );
    });
  });
}
