// Provider-level regression: a consumed final correction after manual navigation
// must settle the transcript boundary without replaying speech or restarting STT.
// Controlled callbacks, not an acoustic replay: user logs omit raw snapshots.
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stt_log_replay_test.dart' as fixture;

const old = 'same pathway is the only way for all of them';
const revised = 'same pathway is the only route for all of them';
const fresh = 'and make no mistake';

Future<fixture.Replay> afterManualJump(WidgetTester tester) async {
  final replay = fixture.Replay(fixture.secondLogScript, 750, 723, 764);
  addTearDown(replay.close);
  replay.hear(old, cumulative: true);
  await tester.pump(const Duration(seconds: 1));
  expect(replay.position, 750);
  replay.notifier.jumpToPosition(681);
  replay.notifier.setVisibleWordWindow(677, 716);
  return replay;
}

void emit(fixture.Replay replay, String text, List<String> alternatives) {
  replay.speech.onResult!(
    SpeechResult(
      text,
      true,
      isCumulative: true,
      streamId: 1,
      alternatives: alternatives,
    ),
  );
}

void main() {
  for (final revision in [
    revised,
    'same pathway is the only safe way for all of them',
    'same pathway is the way for them',
  ]) {
    testWidgets('settled consumed revision permits new append: $revision', (
      tester,
    ) async {
      final r = await afterManualJump(tester);
      final count = r.logs.length;
      r.hear(revision, cumulative: true, finalResult: true);
      expect(r.position, 681);
      expect(
        r.logs.length,
        count,
        reason: 'Bookkeeping is not reading evidence',
      );
      r.hear('$revision $fresh', cumulative: true, finalResult: true);
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, 686, reason: r.logs.join('\n'));
    });
  }

  testWidgets('unchanged append works without a final or stream restart', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear('$old $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('interim retraction and regrowth never replay consumed words', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    final count = r.logs.length;
    r.hear('same pathway', cumulative: true);
    r.hear(old, cumulative: true);
    r.hear(old, cumulative: true, finalResult: true);
    r.hear(old, cumulative: true, finalResult: true);
    expect(r.position, 681);
    expect(r.logs.length, count);
    r.hear('$old $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('fresh alternative wins over a consumed primary correction', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    emit(r, revised, ['$old $fresh']);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
    // A subsequent jump must consume the chosen alternative, not the primary.
    r.notifier.jumpToPosition(681);
    final count = r.logs.length;
    r.hear('$old $fresh', cumulative: true, finalResult: true);
    expect(r.logs.length, count);
    expect(r.position, 681);
  });

  testWidgets('consumed alternatives do not overwrite the primary baseline', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    emit(r, revised, ['same pathway is the only road for everyone']);
    r.hear('$revised $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('repeated manual jumps consume the latest settled snapshot', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(revised, cumulative: true, finalResult: true);
    r.notifier.jumpToPosition(704);
    r.notifier.jumpToPosition(681);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
    r.notifier.jumpToPosition(681);
    final count = r.logs.length;
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    expect(r.position, 681);
    expect(r.logs.length, count);
    r.hear('$revised $fresh $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('ambiguous combined rewrite and append is not replayed', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    final count = r.logs.length;
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    expect(r.position, 681);
    expect(r.logs.length, count);
    // Once settled, genuinely new speech is no longer starved indefinitely.
    r.hear('$revised $fresh $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('post-correction recovery cannot target outside the viewport', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(revised, cumulative: true, finalResult: true);
    r.notifier.setVisibleWordWindow(677, 681);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 681, reason: r.logs.join('\n'));
    r.notifier.setVisibleWordWindow(677, 716);
    r.hear('$revised $fresh $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('new recognizer stream does not inherit the manual boundary', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(revised, cumulative: true, finalResult: true);
    r.hear(fresh, cumulative: true, streamId: 2);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('legacy noncumulative speech remains eligible after a jump', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(fresh);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('stopped session rejects both correction and fresh callbacks', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    await r.notifier.stopSession();
    final count = r.logs.length;
    r.hear(revised, cumulative: true, finalResult: true);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 681);
    expect(r.logs.length, count);
  });

  testWidgets('reset to start uses the same protected correction boundary', (
    tester,
  ) async {
    final script = fixture.passage(0, 'header $fresh $old');
    final end = script.words.length - 1;
    final r = fixture.Replay(script, end, 0, end);
    addTearDown(r.close);
    r.hear(old, cumulative: true);
    r.notifier.resetPosition();
    r.hear(revised, cumulative: true, finalResult: true);
    expect(r.position, 0);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 4, reason: r.logs.join('\n'));
  });

  testWidgets('forward manual navigation also accepts the settled append', (
    tester,
  ) async {
    final script = fixture.passage(0, 'header $old header $fresh');
    final end = script.words.length - 1;
    final target = end - 4;
    final r = fixture.Replay(script, target - 1, 0, end);
    addTearDown(r.close);
    r.hear(old, cumulative: true);
    r.notifier.jumpToPosition(target);
    r.hear(revised, cumulative: true, finalResult: true);
    expect(r.position, target);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, end, reason: r.logs.join('\n'));
  });

  testWidgets('unknown viewport remains fail closed after rebasing', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(revised, cumulative: true, finalResult: true);
    r.notifier.setVisibleWordWindow(null, null);
    r.hear('$revised $fresh', cumulative: true, finalResult: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 681, reason: r.logs.join('\n'));
  });

  testWidgets('duplicates and empty finals cannot reopen pre-jump speech', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    final count = r.logs.length;
    r.hear(revised, cumulative: true, finalResult: true);
    r.hear('$revised.', cumulative: true, finalResult: true);
    r.hear('', cumulative: true, finalResult: true);
    r.hear('...', cumulative: true, finalResult: true);
    r.hear(revised, cumulative: true, finalResult: true);
    expect(r.logs.length, count);
    expect(r.position, 681);
    r.hear('$revised $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('rebasing contributes no evidence toward start threshold', (
    tester,
  ) async {
    final r = await afterManualJump(tester);
    r.hear(revised, cumulative: true, finalResult: true);
    r.hear('$revised and', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 681, reason: r.logs.join('\n'));
    r.hear('$revised $fresh', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('disposed callback cannot process consumed revisions', (
    tester,
  ) async {
    final r = fixture.Replay(fixture.secondLogScript, 681, 677, 716);
    final callback = r.speech.onResult!;
    await r.close();
    expect(
      () => callback(
        SpeechResult(revised, true, isCumulative: true, streamId: 1),
      ),
      returnsNormally,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
