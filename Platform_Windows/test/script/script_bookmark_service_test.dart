import 'package:autoteleprompter/features/script/models/script_word.dart';
import 'package:autoteleprompter/features/script/services/script_bookmark_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
