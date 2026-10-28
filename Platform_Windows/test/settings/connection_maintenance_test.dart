import 'dart:async';
import 'package:autoteleprompter/core/services/connection_maintenance.dart';
import 'package:autoteleprompter/core/services/connection_retry_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'startup, periodic and resume checks never overlap; disposal stops timer',
    (tester) async {
      var calls = 0;
      final held = Completer<void>();
      final maintenance = ConnectionMaintenance([
        () async {
          calls++;
          await held.future;
        },
      ]);
      maintenance.start();
      await tester.pump();
      unawaited(maintenance.checkNow());
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 1);
      held.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 2);
      maintenance.dispose();
      await tester.pump(const Duration(minutes: 10));
      expect(calls, 2);
    },
  );

  test('one provider failure does not block another connection', () async {
    var otherRan = false;
    final maintenance = ConnectionMaintenance([
      () async => throw StateError('offline'),
      () async {
        otherRan = true;
      },
    ]);
    await maintenance.checkNow();
    expect(otherRan, isTrue);
    maintenance.dispose();
  });

  test('retry delay grows to five minutes and clears after recovery', () {
    final gate = ConnectionRetryGate();
    var now = DateTime.utc(2026, 10, 28);
    for (final seconds in [30, 60, 120, 240, 300, 300]) {
      gate.failed(now);
      expect(gate.canAttempt(now.add(Duration(seconds: seconds - 1))), isFalse);
      now = now.add(Duration(seconds: seconds));
      expect(gate.canAttempt(now), isTrue);
    }
    gate.failed(now, requiresSignIn: true);
    expect(gate.canAttempt(now.add(const Duration(days: 10))), isFalse);
    gate.succeeded();
    expect(gate.canAttempt(now), isTrue);
  });
}
