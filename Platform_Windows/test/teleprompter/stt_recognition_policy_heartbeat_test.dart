import 'package:autoteleprompter/features/teleprompter/services/stt_recognition_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host recovery is independent of cloud network retry count', () {
    final now = DateTime(2026, 10, 25, 12);
    expect(
      SttRecognitionPolicyService.browserRecoveryReason(
        now: now,
        sessionStart: now.subtract(const Duration(minutes: 2)),
        lastHeartbeat: now.subtract(const Duration(seconds: 6)),
      ),
      isNull,
    );
    expect(
      SttRecognitionPolicyService.browserRecoveryReason(
        now: now,
        sessionStart: now.subtract(const Duration(minutes: 2)),
        lastHeartbeat: now.subtract(const Duration(seconds: 19)),
      ),
      'stale browser heartbeat',
    );
    expect(
      SttRecognitionPolicyService.browserRecoveryReason(
        now: now,
        sessionStart: now.subtract(const Duration(minutes: 2)),
        lastHeartbeat: null,
      ),
      'missing browser heartbeat',
    );
  });
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
