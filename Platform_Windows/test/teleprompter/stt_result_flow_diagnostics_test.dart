import 'package:autoteleprompter/features/teleprompter/services/stt_result_flow_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'distinguishes filtered callbacks from no results without quiet spam',
    () {
      final d = SttResultFlowDiagnostics();
      final now = DateTime(2026, 10, 25);
      expect(d.takeSummary(now), isNull);
      d.record(filtered: false, now: now);
      d.record(filtered: true, now: now);
      expect(d.takeSummary(now), contains('received=2 eligible=1 filtered=1'));
      expect(d.takeSummary(now.add(const Duration(seconds: 5))), isNull);
      expect(
        d.takeSummary(now.add(const Duration(seconds: 15))),
        contains('lastResultAge=15s'),
      );
      expect(d.takeSummary(now.add(const Duration(seconds: 30))), isNull);
      d.record(filtered: false, now: now.add(const Duration(seconds: 31)));
      expect(
        d.takeSummary(now.add(const Duration(seconds: 32))),
        contains('received=3 eligible=2 filtered=1'),
      );
      d.reset();
      expect(d.takeSummary(now.add(const Duration(seconds: 100))), isNull);
    },
  );
}
