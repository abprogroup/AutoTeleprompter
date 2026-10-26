import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stt_log_replay_test.dart' as fixture;
import 'stt_manual_jump_recovery_test.dart' as manual;

void emit(
  fixture.Replay r,
  List<String> parts, {
  int finalized = 0,
  int stream = 1,
}) => r.speech.onResult!(
  SpeechResult(
    parts.join(' '),
    false,
    isCumulative: true,
    streamId: stream,
    browserSegments: parts,
    browserFinalizedSegmentCount: finalized,
  ),
);

void main() {
  for (final variant in ['replacement', 'insertion', 'deletion']) {
    testWidgets(
      'new result slot survives consumed $variant plus fresh interim',
      (tester) async {
        final r = fixture.Replay(fixture.secondLogScript, 750, 723, 764);
        addTearDown(r.close);
        emit(r, [manual.old]);
        r.notifier.jumpToPosition(681);
        r.notifier.setVisibleWordWindow(677, 716);
        final correction = switch (variant) {
          'insertion' => 'same pathway is the only safe way for all of them',
          'deletion' => 'same pathway is the way for them',
          _ => manual.revised,
        };
        // The old slot settles and a NEW interim slot arrives in one event.
        // No all-final snapshot or recognizer restart occurs between them.
        emit(r, [correction, manual.fresh], finalized: 1);
        await tester.pump(const Duration(seconds: 1));
        expect(r.position, 686, reason: r.logs.join('\n'));
        r.notifier.jumpToPosition(681);
        emit(r, [correction, manual.fresh], finalized: 1);
        await tester.pump(const Duration(seconds: 1));
        expect(
          r.position,
          681,
          reason: 'repeat after a second jump is consumed',
        );
      },
    );
  }
  for (final mode in [
    'same-slot',
    'unfinalized-prefix',
    'offscreen',
    'invalid-parts',
  ]) {
    testWidgets('slot provenance cannot bypass $mode boundary', (tester) async {
      final r = fixture.Replay(fixture.secondLogScript, 750, 723, 764);
      addTearDown(r.close);
      emit(r, [manual.old]);
      r.notifier.jumpToPosition(681);
      r.notifier.setVisibleWordWindow(677, mode == 'offscreen' ? 681 : 716);
      if (mode == 'invalid-parts') {
        r.speech.onResult!(
          SpeechResult(
            '${manual.revised} ${manual.fresh}',
            false,
            isCumulative: true,
            streamId: 1,
            browserSegments: ['bad', manual.fresh],
            browserFinalizedSegmentCount: 1,
          ),
        );
      } else {
        emit(
          r,
          mode == 'same-slot'
              ? ['${manual.revised} ${manual.fresh}']
              : [manual.revised, manual.fresh],
          finalized: mode == 'unfinalized-prefix' ? 0 : 1,
        );
      }
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 681);
    });
  }
}
