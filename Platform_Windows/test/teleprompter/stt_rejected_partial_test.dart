// Real provider callbacks; synthetic analogue of the all-filtered log streak.
// No audio claim: the user's logs do not include the discarded snapshots.
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stt_log_replay_test.dart' as fixture;

const passage =
    'the harbor and the gardens welcomed them after the long journey';
const rejected = 'quantum astronomy';
const correction = 'quantum astrophysics';
const continuation = 'the harbor and the gardens welcomed them';

fixture.Replay setup(WidgetTester tester, {int end = 61}) {
  final r = fixture.Replay(fixture.passage(50, passage), 50, 45, end);
  addTearDown(r.close);
  return r;
}

void emit(fixture.Replay r, String words, {bool finalResult = false}) =>
    r.speech.onResult!(
      SpeechResult(
        words,
        finalResult,
        isCumulative: true,
        streamId: 1,
        browserSegments: [words],
        browserFinalizedSegmentCount: finalResult ? 1 : 0,
      ),
    );

void main() {
  for (final metadata in [false, true]) {
    testWidgets(
      'corrected rejected interim advances before final (slots=$metadata)',
      (tester) async {
        final r = setup(tester);
        void hear(String text) =>
            metadata ? emit(r, text) : r.hear(text, cumulative: true);
        hear(rejected);
        expect(r.logs.last, contains('TRACK_RESET_OFF_SCRIPT'));
        for (final text in [
          correction,
          '$correction the harbor',
          '$correction the harbor and the gardens',
          '$correction $continuation',
        ]) {
          hear(text);
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pump(const Duration(seconds: 2));
        expect(r.position, 56, reason: r.logs.join('\n'));
      },
    );
  }

  for (final mode in [
    'offscreen',
    'unknown',
    'single-word',
    'repeated-short',
    'unrelated',
  ]) {
    testWidgets('rejected interim does not bypass $mode safety', (
      tester,
    ) async {
      final r = setup(tester, end: mode == 'offscreen' ? 50 : 61);
      if (mode == 'unknown') r.notifier.setVisibleWordWindow(null, null);
      emit(r, rejected);
      final text = switch (mode) {
        'single-word' => '$correction welcomed',
        'repeated-short' => '$correction gardens welcomed',
        'unrelated' => '$correction the mountain trail is empty',
        _ => '$correction $continuation',
      };
      for (var n = 0; n < 5; n++) {
        emit(r, text);
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 50, reason: r.logs.join('\n'));
    });
  }

  testWidgets(
    'manual jump keeps consumed speech protected through corrections',
    (tester) async {
      final r = setup(tester);
      emit(r, rejected);
      r.notifier.jumpToPosition(50);
      emit(r, '$correction $continuation');
      emit(r, '$correction $continuation', finalResult: true);
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 50);
      // A genuine new recognizer generation remains eligible.
      r.hear(continuation, cumulative: true, streamId: 2);
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 56, reason: r.logs.join('\n'));
    },
  );

  testWidgets(
    'already accepted speech is not reopened by an interim rejection',
    (tester) async {
      final script = fixture.passage(50, '$passage $passage');
      final r = fixture.Replay(script, 50, 45, script.words.length - 1);
      addTearDown(r.close);
      emit(r, continuation);
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 56);
      emit(r, '$continuation $rejected');
      emit(r, '$continuation $correction');
      emit(r, continuation); // An interim retraction cannot recycle the prefix.
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 56, reason: r.logs.join('\n'));
    },
  );

  testWidgets(
    'rejected final settles while stable new appends remain eligible',
    (tester) async {
      final r = setup(tester);
      emit(r, rejected, finalResult: true);
      for (var n = 0; n < 3; n++) {
        emit(r, rejected, finalResult: true);
      }
      expect(r.position, 50);
      r.speech.onResult!(
        SpeechResult(
          '$rejected $continuation',
          false,
          isCumulative: true,
          streamId: 1,
          browserSegments: [rejected, continuation],
          browserFinalizedSegmentCount: 1,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, 56, reason: r.logs.join('\n'));
    },
  );

  testWidgets('stop rejects corrected callbacks without reviving the session', (
    tester,
  ) async {
    final r = setup(tester);
    emit(r, rejected);
    await r.notifier.stopSession();
    emit(r, '$correction $continuation');
    await tester.pump(const Duration(seconds: 2));
    expect(r.position, 50);
  });
}
