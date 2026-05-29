import 'dart:convert';

import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/script/services/script_bookmark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScriptWord _word(
  String raw,
  int index, {
  bool isNewline = false,
}) {
  return ScriptWord(
    raw: raw,
    normalized: raw.toLowerCase(),
    index: index,
    isRtl: false,
    isNewline: isNewline,
  );
}

void main() {
  group('ScriptBookmarkService presenter target bounds', () {
    test('leading invisible position resolves to first real word', () {
      final words = [
        _word('\n\n', 0, isNewline: true),
        _word('[align=center]', 1),
        _word('Start', 2),
        _word('middle', 3),
      ];

      expect(ScriptBookmarkService.nearestBookmarkableWordIndex(words, 0), 2);
    });

    test('trailing invisible position resolves to last real word', () {
      final words = [
        _word('Start', 0),
        _word('finish', 1),
        _word('\n\n', 2, isNewline: true),
      ];

      expect(ScriptBookmarkService.nearestBookmarkableWordIndex(words, 99), 1);
    });

    test('all invisible script has no bookmark target', () {
      final words = [
        _word('\n\n', 0, isNewline: true),
        _word('[align=right]', 1),
      ];

      expect(
          ScriptBookmarkService.nearestBookmarkableWordIndex(words, 0), isNull);
    });
  });

  group('ScriptBookmarkService encrypted persistence', () {
    test('load migrates legacy plaintext bookmarks and removes old key',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final key = ScriptBookmarkService.scopeKey(
        'session-privacy-test',
        'Sensitive script title',
      );
      await prefs.setStringList(key, [
        jsonEncode({
          'id': 'bookmark-1',
          'label': 'Private bookmark phrase',
          'wordIndex': 4,
          'blockIndex': 1,
          'offset': 12,
          'createdAt': '2026-05-28T20:00:00.000Z',
        }),
      ]);

      final loaded = await ScriptBookmarkService.load(key);
      final secureRaw = prefs.getString('$key.secure');

      expect(loaded, hasLength(1));
      expect(loaded.single.label, 'Private bookmark phrase');
      expect(prefs.getStringList(key), isNull);
      expect(secureRaw, isNotNull);
      expect(secureRaw, isNot(contains('Private bookmark phrase')));
    });
  });
}
