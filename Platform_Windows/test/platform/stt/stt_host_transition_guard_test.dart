import 'package:flutter_test/flutter_test.dart';
import 'package:autoteleprompter/platform/stt/stt_host_transition_guard.dart';

void main() {
  group('SttHostTransitionGuard', () {
    test('only the active lease can release a transition', () {
      final guard = SttHostTransitionGuard();
      final first = guard.begin();

      expect(guard.isActive, isTrue);
      expect(guard.owns(first), isTrue);
      expect(guard.release(first), isTrue);
      expect(guard.isActive, isFalse);
    });

    test('a stale completion cannot clear a newer transition', () {
      final guard = SttHostTransitionGuard();
      final stale = guard.begin();
      guard.invalidate();
      final current = guard.begin();

      expect(guard.release(stale), isFalse);
      expect(guard.isActive, isTrue);
      expect(guard.owns(current), isTrue);
      expect(guard.release(current), isTrue);
      expect(guard.isActive, isFalse);
    });
  });
}
