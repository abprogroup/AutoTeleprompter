import 'package:autoteleprompter/features/teleprompter/providers/teleprompter_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stt_log_replay_test.dart' as fixture;

const oldSpeech = 'same pathway is the only way for all of them';
const freshSpeech = 'and make no mistake';

fixture.Replay prepare() {
  final r = fixture.Replay(fixture.secondLogScript, 750, 723, 764);
  addTearDown(r.close);
  r.hear(oldSpeech, cumulative: true);
  expect(r.notifier.beginManualScroll(), isTrue);
  return r;
}

void commit(fixture.Replay r) {
  r.notifier.setVisibleWordWindow(677, 716);
  r.notifier.finishManualScroll(681, script: fixture.secondLogScript);
  expect(r.position, 681);
  expect(r.notifier.manualScrollInProgress, isFalse);
}

void main() {
  for (final retraction in ['.', 'and']) {
    testWidgets('held interim $retraction cannot reopen consumed speech', (
      tester,
    ) async {
      const consumed =
          "and make no mistake home's room is big enough for the entire fleet";
      final r = fixture.Replay(fixture.secondLogScript, 750, 723, 764);
      addTearDown(r.close);
      r.hear(consumed, cumulative: true);
      expect(r.notifier.beginManualScroll(), isTrue);
      r.hear(retraction, cumulative: true);
      commit(r);
      r.hear(consumed, cumulative: true);
      await tester.pump(const Duration(seconds: 2));
      expect(
        r.position,
        681,
        reason:
            'Pre-navigation speech must remain consumed.\n${r.logs.join('\n')}',
      );
      r.hear(
        '$consumed He cares about the worker in Santa New Marbella',
        cumulative: true,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(r.position, greaterThan(681), reason: r.logs.join('\n'));
      expect(r.position, lessThanOrEqualTo(716));
    });
  }

  testWidgets('moving consumes old primary and allows immediate fresh suffix', (
    tester,
  ) async {
    final r = prepare();
    r.hear('$oldSpeech today', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 750);
    commit(r);
    r.hear('$oldSpeech today', cumulative: true, finalResult: true);
    expect(r.position, 681);
    r.hear('$oldSpeech today $freshSpeech', cumulative: true);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets(
    'new stream arriving during gesture is consumed, its suffix is fresh',
    (tester) async {
      final r = prepare();
      r.hear('old detached phrase', cumulative: true, streamId: 2);
      commit(r);
      r.hear('old detached phrase $freshSpeech', cumulative: true, streamId: 2);
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, 686, reason: r.logs.join('\n'));
    },
  );

  testWidgets('new stream after gesture does not inherit consumed speech', (
    tester,
  ) async {
    final r = prepare();
    commit(r);
    r.hear(freshSpeech, cumulative: true, streamId: 2);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('gesture consumes legacy shards without invoking commands', (
    tester,
  ) async {
    final r = prepare();
    r.hear('speed up and make no mistake');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 750);
    expect(r.logs.any((line) => line.contains('VOICE COMMAND:')), isFalse);
    commit(r);
    r.hear(freshSpeech);
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 686, reason: r.logs.join('\n'));
  });

  testWidgets('offscreen and unknown viewport still fail after commit', (
    tester,
  ) async {
    for (final unknown in [false, true]) {
      final r = prepare();
      commit(r);
      r.notifier.setVisibleWordWindow(
        unknown ? null : 677,
        unknown ? null : 683,
      );
      r.hear(freshSpeech, cumulative: true, streamId: 2);
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, lessThanOrEqualTo(unknown ? 681 : 683));
    }
  });

  testWidgets('explicit jump supersedes late scroll completion', (
    tester,
  ) async {
    final r = prepare();
    r.notifier.jumpToPosition(700);
    expect(r.notifier.manualScrollInProgress, isFalse);
    r.notifier.finishManualScroll(681, script: fixture.secondLogScript);
    expect(r.position, 700);
  });

  testWidgets('stop and reset release hold without a delayed anchor jump', (
    tester,
  ) async {
    final r = prepare();
    r.notifier.resetPosition();
    r.notifier.finishManualScroll(681, script: fixture.secondLogScript);
    expect(r.position, 0);
    expect(r.notifier.beginManualScroll(), isTrue);
    await r.notifier.stopSession();
    r.notifier.finishManualScroll(681, script: fixture.secondLogScript);
    r.speech.onResult!(SpeechResult(freshSpeech, false));
    expect(r.position, 0);
    expect(r.notifier.manualScrollInProgress, isFalse);
    expect(r.notifier.beginManualScroll(), isFalse);
  });
}
