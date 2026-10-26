import 'package:flutter_test/flutter_test.dart';

import 'stt_log_replay_test.dart' as fixture;

void main() {
  testWidgets('locale pre-switch does not return to the animated old language', (
    tester,
  ) async {
    final script = fixture.passage(
      0,
      'start ${List.filled(20, 'filler').join(' ')} אנשים קוראים טקסט ברור וממשיכים הלאה',
    );
    final r = fixture.Replay(script, 0, 0, script.words.length - 1);
    addTearDown(r.close);
    r.hear('אנשים קוראים טקסט ברור');
    expect(
      r.logs.any((l) => l.contains('-> he_IL (advance)')),
      isTrue,
      reason: r.logs.join('\n'),
    );
    await tester.pump(const Duration(milliseconds: 160));
    final before = r.logs.length;
    r.hear('אה'); // uncertain interim must not restart back at old English line
    expect(
      r.logs.skip(before).where((l) => l.contains('-> en_US')),
      isEmpty,
      reason: r.logs.join('\n'),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(r.position, 24);
  });
  testWidgets('rapid fresh results do not keep postponing the visual tick', (
    tester,
  ) async {
    final following = 'carefully we also use these words to finish the example'
        .split(' ');
    final script = fixture.passage(
      0,
      'start ${List.filled(20, 'filler').join(' ')} qualified readers review transcripts ${following.join(' ')}',
    );
    final r = fixture.Replay(script, 0, 0, script.words.length - 1);
    addTearDown(r.close);
    r.hear('qualified readers review transcripts');
    for (final word in following) {
      await tester.pump(const Duration(milliseconds: 20));
      r.hear(word);
    }
    expect(
      r.position,
      greaterThanOrEqualTo(2),
      reason: 'partials must not starve animation',
    );
    await tester.pump(const Duration(seconds: 4));
    expect(r.position, script.words.length - 1, reason: r.logs.join('\n'));
  });
  testWidgets('continuation follows accepted target while paint catches up', (
    tester,
  ) async {
    final script = fixture.passage(
      0,
      'start ${List.filled(25, 'filler').join(' ')} '
      'qualified readers review transcripts '
      'Carefully we also use this verse to say male and female do not exist '
      'Do readers follow the next paragraph',
    );
    final r = fixture.Replay(script, 0, 0, script.words.length - 1);
    addTearDown(r.close);
    final accepted = script.words.indexWhere((w) => w.raw == 'transcripts');
    r.hear('qualified readers review transcripts');
    await tester.pump(const Duration(milliseconds: 500));
    expect(r.position, lessThan(accepted));
    final before = r.logs.length;
    r.hear('Carefully');
    await tester.pump(const Duration(seconds: 5));
    expect(r.position, accepted + 1, reason: r.logs.join('\n'));
    expect(
      r.logs.skip(before).any((l) => l.contains('TRACK_RESET_OFF_SCRIPT')),
      isFalse,
    );
  });

  for (final boundary in ['offscreen', 'unknown', 'manual', 'stop']) {
    testWidgets('in-flight acceptance cannot survive $boundary boundary', (
      tester,
    ) async {
      final script = fixture.passage(
        0,
        'start ${List.filled(20, 'filler').join(' ')} '
        'a solution for every person on earth regardless of background '
        'But can we also use this verse',
      );
      final r = fixture.Replay(script, 0, 0, script.words.length - 1);
      addTearDown(r.close);
      r.hear('a solution for every person on earth regardless of background');
      await tester.pump(const Duration(milliseconds: 160));
      if (boundary == 'offscreen') r.notifier.setVisibleWordWindow(0, 10);
      if (boundary == 'unknown') r.notifier.setVisibleWordWindow(null, null);
      if (boundary == 'manual') r.notifier.jumpToPosition(2);
      if (boundary == 'stop') await r.notifier.stopSession();
      final position = r.position;
      // No new speech is permission to resume a previously cancelled target.
      await tester.pump(const Duration(seconds: 5));
      expect(r.position, position);
      if (boundary == 'offscreen' ||
          boundary == 'unknown' ||
          boundary == 'stop') {
        r.hear('But can we also use this verse');
        await tester.pump(const Duration(seconds: 5));
        expect(r.position, position);
      }
    });
  }
}
