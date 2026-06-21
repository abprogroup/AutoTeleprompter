import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

List<ScriptWord> _words(List<String> raw) {
  return [
    for (var i = 0; i < raw.length; i++) _word(raw[i], i),
  ];
}

void main() {
  group('iOS V5 STT recognition policy', () {
    test('normal mode does not advance from one unlocked word', () {
      final script = _words(['intro', 'alpha', 'beta', 'gamma']);

      final oneWord = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
      );

      expect(oneWord.confirmedWordIndex, 0);
      expect(oneWord.decision, SttAlignmentDecision.wait);
    });

    test('normal mode advances after the start threshold is met', () {
      final script = _words(['intro', 'one', 'two', 'red', 'sun']);

      final result = WordAligner.align(
        script: script,
        transcript: 'one two red sun',
        lastConfirmedIndex: 0,
      );

      expect(result.confirmedWordIndex, 4);
      expect(result.decision, SttAlignmentDecision.advance);
    });

    test('normal standby does not skip required words for one later match', () {
      final script = _words([
        'Today',
        'we',
        'are',
        'thrilled',
        'to',
        'announce',
        'a',
        'completely',
        'new',
        'way',
        'to',
        'deliver',
        'your',
        'message',
        'to',
        'the',
        'world',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript:
            'we are thrilled to announce a completely new way to deliver the',
        lastConfirmedIndex: 11,
        readingStandby: true,
      );

      expect(result.confirmedWordIndex, 11);
      expect(result.decision, SttAlignmentDecision.wait);
    });

    test('normal mode does not advance into an unspoken following word', () {
      final script = _words([
        'Today',
        'we',
        'are',
        'thrilled',
        'to',
        'announce',
        'a',
        'completely',
        'new',
        'way',
        'to',
        'deliver',
        'your',
        'message',
        'to',
        'the',
        'world',
      ]);

      final result = WordAligner.align(
        script: script,
        transcript: 'a completely new way to deliver your message',
        lastConfirmedIndex: 10,
      );

      expect(result.confirmedWordIndex, 13);
      expect(script[result.confirmedWordIndex].raw, 'message');
      expect(result.decision, SttAlignmentDecision.advance);
    });

    test('bullet mode requires two big words or three small words', () {
      final script = _words(['intro', 'alpha', 'bravo', 'one', 'two', 'red']);

      final singleBig = WordAligner.align(
        script: script,
        transcript: 'alpha',
        lastConfirmedIndex: 0,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );
      final twoBig = WordAligner.align(
        script: script,
        transcript: 'alpha bravo',
        lastConfirmedIndex: 0,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );
      final threeSmall = WordAligner.align(
        script: script,
        transcript: 'one two red',
        lastConfirmedIndex: 2,
        policy: SttRecognitionPolicy.legacy(strictBulletMode: true),
      );

      expect(singleBig.decision, SttAlignmentDecision.wait);
      expect(twoBig.confirmedWordIndex, 2);
      expect(twoBig.decision, SttAlignmentDecision.advance);
      expect(threeSmall.confirmedWordIndex, 5);
      expect(threeSmall.decision, SttAlignmentDecision.advance);
    });
  });
}
