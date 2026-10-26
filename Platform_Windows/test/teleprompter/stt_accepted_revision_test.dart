import 'package:flutter_test/flutter_test.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_accepted_revision_service.dart';

import 'stt_log_replay_test.dart' as fixture;

void main() {
  test(
    'revision provenance is exact bounded context, never fuzzy evidence',
    () {
      final service = SttAcceptedRevisionService();
      final now = DateTime(2026, 10, 25);
      service.remember(
        transcript: 'you readers chose 2022 and finished',
        target: 10,
        now: now,
      );
      bool revision(String text, {int target = 10, int seconds = 1}) =>
          service.isRevision(
            transcript: text,
            currentIndex: target,
            now: now.add(Duration(seconds: seconds)),
          );
      expect(revision('You readers chose 2022 and finished.'), isTrue);
      expect(revision('2022 and finished.'), isTrue);
      for (final text in [
        'finished',
        'you readers chose 2022 and',
        '2020 and finished',
        '20.22 and finished',
        '20-22 and finished',
        '-2022 and finished',
        '2022 and started',
        '2022 and finished today',
        'very very',
        '',
      ]) {
        expect(revision(text), isFalse, reason: text);
      }
      expect(revision('2022 and finished', target: 11), isFalse);
      expect(revision('2022 and finished', seconds: 9), isFalse);
      expect(revision('2022 and finished', seconds: -1), isFalse);
      service.reset();
      expect(revision('2022 and finished'), isFalse);
    },
  );

  for (final boundary in [
    'manual',
    'stream',
    'offscreen',
    'unknown',
    'stop',
    'aside',
  ]) {
    testWidgets('accepted revision cannot outlive $boundary boundary', (
      tester,
    ) async {
      final script = fixture.passage(
        0,
        'begin the speaker addresses readers young old slave or free are all welcome in this room',
      );
      final r = fixture.Replay(script, 0, 0, script.words.length - 1);
      addTearDown(r.close);
      r.hear('the speaker addresses readers young old');
      await tester.pump(const Duration(seconds: 1));
      r.hear(
        'is saying that you readers young old slave or free',
        cumulative: true,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, 9);
      if (boundary == 'manual') r.notifier.jumpToPosition(9);
      if (boundary == 'offscreen') r.notifier.setVisibleWordWindow(10, 15);
      if (boundary == 'unknown') r.notifier.setVisibleWordWindow(null, null);
      if (boundary == 'stop') await r.notifier.stopSession();
      if (boundary == 'aside') {
        r.hear('unrelated conversation about supper', cumulative: true);
      }
      final before = r.logs.length;
      r.hear(
        'is saying that you readers young, old, slave or free.',
        cumulative: true,
        finalResult: true,
        streamId: boundary == 'stream' ? 2 : 1,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(r.position, 9);
      expect(
        r.logs
            .skip(before)
            .where((l) => l.contains('already_confirmed_revision')),
        isEmpty,
      );
    });
  }

  testWidgets('a fresh suffix still advances through the ordinary policy', (
    tester,
  ) async {
    final script = fixture.passage(
      0,
      'begin the speaker addresses readers young old slave or free are all welcome in this room',
    );
    final r = fixture.Replay(script, 0, 0, script.words.length - 1);
    addTearDown(r.close);
    r.hear('the speaker addresses readers young old');
    await tester.pump(const Duration(seconds: 1));
    r.hear(
      'is saying that you readers young old slave or free',
      cumulative: true,
    );
    await tester.pump(const Duration(seconds: 1));
    r.hear(
      'is saying that you readers young old slave or free are all welcome',
      cumulative: true,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 12, reason: r.logs.join('\n'));
    final position = r.position;
    await tester.pump(const Duration(seconds: 15));
    expect(r.position, position, reason: 'silence cannot supply evidence');
  });

  testWidgets('accepted imperfect phrase revision cannot reset tracking', (
    tester,
  ) async {
    final script = fixture.passage(
      0,
      'begin the speaker addresses readers young old slave or free '
      'are all welcome in this room',
    );
    final r = fixture.Replay(script, 0, 0, script.words.length - 1);
    addTearDown(r.close);
    r.hear('the speaker addresses readers young old');
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 6);
    r.hear(
      'is saying that you readers young old slave or free',
      cumulative: true,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(r.position, 9, reason: r.logs.join('\n'));
    final before = r.logs.length;
    r.hear(
      'is saying that you readers young, old, slave or free.',
      cumulative: true,
      finalResult: true,
    );
    expect(
      r.logs.skip(before).where((l) => l.contains('TRACK_RESET_OFF_SCRIPT')),
      isEmpty,
      reason: r.logs.join('\n'),
    );
    expect(r.position, 9, reason: 'a revision is not new speech evidence');
    r.hear('are');
    await tester.pump(const Duration(milliseconds: 200));
    expect(r.position, 10, reason: r.logs.join('\n'));
  });
}
