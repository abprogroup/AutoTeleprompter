import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/approximate_spoken_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _hDira = '\u05d3\u05d9\u05e8\u05d4';
const _hHadashim = '\u05d7\u05d3\u05e9\u05d9\u05dd';
const _hKamah = '\u05db\u05de\u05d4';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

void main() {
  const service = ApproximateSpokenSearchService();

  test('finds an exact English spoken phrase', () {
    final words = [
      _word('the', 0),
      _word('coolest', 1),
      _word('part', 2),
      _word('was', 3),
      _word('not', 4),
      _word('the', 5),
      _word('speed', 6),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'coolest part was not the speed',
    );

    expect(match, isNotNull);
    expect(match!.startWordIndex, 1);
    expect(match.endWordIndex, 6);
    expect(match.score, greaterThan(0.98));
  });

  test('tolerates missing or misrecognized words in a longer phrase', () {
    final words = [
      _word('both', 0),
      _word('of', 1),
      _word('them', 2),
      _word('are', 3),
      _word('good', 4),
      _word('business', 5),
      _word('people', 6),
      _word('right', 7),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'both of them good business peoples',
    );

    expect(match, isNotNull);
    expect(match!.startWordIndex, 0);
    expect(match.endWordIndex, 6);
    expect(match.score, greaterThan(0.74));
  });

  test('searches Hebrew text after removing markup and niqqud', () {
    final words = [
      _word('[g]$_hDira', 0, rtl: true),
      _word(_hHadashim, 1, rtl: true),
      _word('50', 2),
      _word(_hKamah, 3, rtl: true),
    ];

    final match = service.findBest(
      words: words,
      spokenText: '$_hDira $_hHadashim',
    );

    expect(match, isNotNull);
    expect(match!.startWordIndex, 0);
    expect(match.endWordIndex, 1);
    expect(match.matchedText, '$_hDira $_hHadashim');
  });

  test('ignores style tags while keeping visible mixed tokens searchable', () {
    final words = [
      _word('[bg=#00ff00][u]EP85', 0),
      _word('camera-ready[/u]', 1),
      _word('[size=72]$_hDira', 2, rtl: true),
      _word('2026', 3),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'EP85 camera ready $_hDira 2026',
    );

    expect(match, isNotNull);
    expect(match!.startWordIndex, 0);
    expect(match.endWordIndex, 3);
    expect(match.score, greaterThan(0.80));
  });

  test('rejects unrelated short phrases', () {
    final words = [
      _word('video', 0),
      _word('scripts', 1),
      _word('opening', 2),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'camera',
    );

    expect(match, isNull);
  });

  test('returns ranked non-overlapping phrase matches', () {
    final words = [
      _word('the', 0),
      _word('coolest', 1),
      _word('part', 2),
      _word('was', 3),
      _word('slow', 4),
      _word('then', 5),
      _word('the', 6),
      _word('coolest', 7),
      _word('part', 8),
      _word('was', 9),
      _word('fast', 10),
    ];

    final matches = service.findRanked(
      words: words,
      spokenText: 'the coolest part was',
      limit: 5,
    );

    expect(matches, hasLength(2));
    expect(matches.map((m) => m.startWordIndex), containsAll([0, 6]));
    expect(matches.every((m) => m.score > 0.98), isTrue);
  });

  test('finds a target phrase embedded inside a long spoken paragraph', () {
    final words = [
      _word('opening', 0),
      _word('title', 1),
      _word('both', 2),
      _word('of', 3),
      _word('them', 4),
      _word('are', 5),
      _word('good', 6),
      _word('business', 7),
      _word('people', 8),
      _word('right', 9),
      _word('closing', 10),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'before that i was explaining the setup and then '
          'both of them are good business people right but i kept talking '
          'after the useful phrase too',
    );

    expect(match, isNotNull);
    expect(match!.startWordIndex, 2);
    expect(match.endWordIndex, 9);
    expect(match.score, greaterThan(0.88));
  });

  test('long spoken text still rejects unrelated script content', () {
    final words = [
      _word('camera', 0),
      _word('settings', 1),
      _word('recording', 2),
      _word('folder', 3),
      _word('preview', 4),
    ];

    final match = service.findBest(
      words: words,
      spokenText: 'before that i was explaining the setup and then '
          'both of them are good business people right but i kept talking '
          'after the useful phrase too',
    );

    expect(match, isNull);
  });
}
