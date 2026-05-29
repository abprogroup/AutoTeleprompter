import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/teleprompter/services/stt_visible_relock_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _hDira = '\u05d3\u05d9\u05e8\u05d4';
const _hHadashim = '\u05d7\u05d3\u05e9\u05d9\u05dd';

ScriptWord _word(String raw, int index, {bool rtl = false}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: rtl,
  );
}

void main() {
  const service = SttVisibleRelockService();

  test('fuzzy relock accepts reversed visible windows', () {
    final words = [
      _word('title', 0),
      _word('both', 1),
      _word('of', 2),
      _word('them', 3),
      _word('are', 4),
      _word('good', 5),
      _word('footer', 6),
    ];

    final target = service.fuzzyTarget(
      words: words,
      transcript: 'both of them are good',
      visibleWordStart: 5,
      visibleWordEnd: 1,
    );

    expect(target, 5);
  });

  test('approximate relock advances only beyond current reading index', () {
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

    final target = service.approximateTarget(
      words: words,
      transcript: 'both of them are good business people right',
      currentIndex: 7,
      visibleWordStart: 0,
      visibleWordEnd: 7,
    );

    expect(target, isNull);
  });

  test('approximate relock ignores hidden markup inside visible words', () {
    final words = [
      _word('[bg=#00ff00]$_hDira', 0, rtl: true),
      _word('[u]$_hHadashim[/u]', 1, rtl: true),
      _word('camera-ready', 2),
      _word('2026', 3),
      _word('done', 4),
    ];

    final target = service.approximateTarget(
      words: words,
      transcript: '$_hDira $_hHadashim camera ready 2026',
      currentIndex: -1,
      visibleWordStart: 0,
      visibleWordEnd: 4,
      minimumScore: 0.80,
    );

    expect(target, 3);
  });

  test('global approximate relock can recover when visible window is stale', () {
    final words = [
      _word('1', 0),
      _word('Video', 1),
      _word('Scripts', 2),
      _word('intro', 3),
      _word('both', 4),
      _word('of', 5),
      _word('them', 6),
      _word('are', 7),
      _word('good', 8),
      _word('business', 9),
      _word('people', 10),
      _word('right', 11),
      _word('but', 12),
      _word('that', 13),
      _word('was', 14),
    ];

    final visibleOnly = service.approximateTarget(
      words: words,
      transcript: 'both of them are good business people right',
      currentIndex: 0,
      visibleWordStart: 0,
      visibleWordEnd: 2,
      minimumScore: 0.80,
    );
    final global = service.globalApproximateTarget(
      words: words,
      transcript: 'both of them are good business people right',
      currentIndex: 0,
      minimumScore: 0.84,
    );

    expect(visibleOnly, isNull);
    expect(global, 11);
  });

  test('visible approximate relock can use phrase inside long paragraph', () {
    final words = [
      _word('1', 0),
      _word('Video', 1),
      _word('Scripts', 2),
      _word('both', 3),
      _word('of', 4),
      _word('them', 5),
      _word('are', 6),
      _word('good', 7),
      _word('business', 8),
      _word('people', 9),
      _word('right', 10),
      _word('closing', 11),
    ];

    final target = service.approximateTarget(
      words: words,
      transcript: 'i was explaining something before the useful part then '
          'both of them are good business people right but i kept speaking '
          'with many extra words after the match',
      currentIndex: 0,
      visibleWordStart: 0,
      visibleWordEnd: 11,
      minimumScore: 0.76,
    );

    expect(target, 10);
  });

  test('global approximate relock ignores short uncertain phrases', () {
    final words = [
      _word('1', 0),
      _word('Video', 1),
      _word('Scripts', 2),
      _word('both', 3),
      _word('of', 4),
      _word('them', 5),
      _word('are', 6),
      _word('good', 7),
      _word('business', 8),
      _word('people', 9),
    ];

    final target = service.globalApproximateTarget(
      words: words,
      transcript: 'good business people',
      currentIndex: 0,
      minimumScore: 0.80,
    );

    expect(target, isNull);
  });

  test('global approximate relock never moves behind the current word', () {
    final words = [
      _word('both', 0),
      _word('of', 1),
      _word('them', 2),
      _word('are', 3),
      _word('good', 4),
      _word('business', 5),
      _word('people', 6),
      _word('right', 7),
      _word('next', 8),
      _word('section', 9),
    ];

    final target = service.globalApproximateTarget(
      words: words,
      transcript: 'both of them are good business people right',
      currentIndex: 7,
      minimumScore: 0.80,
    );

    expect(target, isNull);
  });
}
