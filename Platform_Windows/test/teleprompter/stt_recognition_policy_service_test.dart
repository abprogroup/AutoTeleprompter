import 'package:autoteleprompter/features/teleprompter/services/stt_recognition_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Browser speech recovery policy', () {
    test('recovers when initial WebView heartbeat never arrives', () {
      final now = DateTime(2026, 5, 29, 7);

      final reason = SttRecognitionPolicyService.browserRecoveryReason(
        now: now,
        sessionStart: now.subtract(const Duration(seconds: 19)),
        lastHeartbeat: null,
        lastRecoverableError: null,
        recoverableErrorCount: 0,
      );

      expect(reason, 'missing browser heartbeat');
    });

    test('does not recover before the initial heartbeat grace window', () {
      final now = DateTime(2026, 5, 29, 7);

      final reason = SttRecognitionPolicyService.browserRecoveryReason(
        now: now,
        sessionStart: now.subtract(const Duration(seconds: 10)),
        lastHeartbeat: null,
        lastRecoverableError: null,
        recoverableErrorCount: 0,
      );

      expect(reason, isNull);
    });

    test('recovers stale heartbeat and repeated recoverable errors', () {
      final now = DateTime(2026, 5, 29, 7);

      expect(
        SttRecognitionPolicyService.browserRecoveryReason(
          now: now,
          sessionStart: now.subtract(const Duration(minutes: 1)),
          lastHeartbeat: now.subtract(const Duration(seconds: 19)),
          lastRecoverableError: null,
          recoverableErrorCount: 0,
        ),
        'stale browser heartbeat',
      );

      expect(
        SttRecognitionPolicyService.browserRecoveryReason(
          now: now,
          sessionStart: now.subtract(const Duration(minutes: 1)),
          lastHeartbeat: now,
          lastRecoverableError: now.subtract(const Duration(seconds: 4)),
          recoverableErrorCount: 3,
        ),
        'recoverable browser errors',
      );
    });
  });
}
