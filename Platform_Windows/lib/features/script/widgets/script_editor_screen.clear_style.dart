part of 'script_editor_screen.dart';

extension _ScriptEditorClearStyleParts on _ScriptEditorScreenState {
  /// Clear style at cursor by stripping tags from the current word while
  /// preserving surrounding styled text.
  void _clearStyleAtCursor(MarkupController c, int cursor) {
    final text = c.text;
    final tagPattern = RegExp(
        r'\[\/?(?:u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');

    int wordStart = cursor;
    int wordEnd = cursor;

    while (wordStart > 0) {
      final prev = wordStart - 1;
      var skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.end == wordStart) {
          wordStart = m.start;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      final ch = text[prev];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordStart = prev;
    }

    while (wordEnd < text.length) {
      var skippedTag = false;
      for (final m in tagPattern.allMatches(text)) {
        if (m.start == wordEnd) {
          wordEnd = m.end;
          skippedTag = true;
          break;
        }
      }
      if (skippedTag) continue;
      final ch = text[wordEnd];
      if (ch == ' ' || ch == '\n' || ch == '\t') break;
      wordEnd++;
    }

    if (wordStart >= wordEnd) return;

    final before = text.substring(0, wordStart);
    final wordContent = text.substring(wordStart, wordEnd);
    final after = text.substring(wordEnd);
    final cleanWord = wordContent.replaceAll(tagPattern, '');

    var result = before + cleanWord + after;
    final tagsBeforeCursor = tagPattern.allMatches(wordContent.substring(
        0, (cursor - wordStart).clamp(0, wordContent.length)));
    var removedBefore = 0;
    for (final m in tagsBeforeCursor) {
      removedBefore += m.end - m.start;
    }
    var newCursor = (cursor - removedBefore).clamp(0, result.length);

    final wordStartInResult = wordStart;
    final wordEndInResult = wordStart + cleanWord.length;
    result = _splitAllEnclosingStyles(
      result,
      wordStartInResult,
      wordEndInResult,
      tagPattern,
    );
    newCursor = newCursor.clamp(0, result.length);

    c.value = TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  /// Split every enclosing style tag pair around a range so the selected range
  /// loses styling while surrounding text keeps it.
  String _splitAllEnclosingStyles(
      String text, int start, int end, RegExp tagPattern) {
    final families = <String, List<String>>{
      'bold': ['**', '**'],
      'underline': ['[u]', '[/u]'],
      'italic': ['[i]', '[/i]'],
    };
    final paramFamilies = ['color', 'bg', 'size', 'font', 'align'];

    var current = text;
    var curStart = start;
    var curEnd = end;

    for (final entry in families.entries) {
      final result = _splitEnclosingStyle(
          current, curStart, curEnd, entry.value[0], entry.value[1]);
      if (result != null) {
        current = result[0] as String;
        curStart = result[1] as int;
        curEnd = result[2] as int;
      }
    }
    for (final family in paramFamilies) {
      final openPattern = RegExp(r'\[' + family + r'=[^\]]+\]');
      final close = '[/$family]';
      for (final m in openPattern.allMatches(current)) {
        if (m.start <= curStart) {
          final closeIdx = current.indexOf(close, m.end);
          if (closeIdx != -1 && closeIdx >= curEnd) {
            final result = _splitEnclosingStyle(
              current,
              curStart,
              curEnd,
              current.substring(m.start, m.end),
              close,
            );
            if (result != null) {
              current = result[0] as String;
              curStart = result[1] as int;
              curEnd = result[2] as int;
            }
            break;
          }
        }
      }
    }
    return current;
  }

  /// Find an enclosing open/close pair around a cursor.
  List<int>? _findEnclosingPair(
      String text, int cursor, String open, String close) {
    if (open == '**' && close == '**') {
      final matches = RegExp(r'\*\*').allMatches(text).toList();
      for (var i = 0; i < matches.length - 1; i += 2) {
        final oStart = matches[i].start;
        final oEnd = matches[i].end;
        if (i + 1 < matches.length) {
          final cStart = matches[i + 1].start;
          final cEnd = matches[i + 1].end;
          if (oEnd <= cursor && cStart >= cursor) {
            return [oStart, oEnd, cStart, cEnd];
          }
        }
      }
      return null;
    }
    var searchFrom = cursor;
    while (searchFrom >= 0) {
      final idx = text.lastIndexOf(open, searchFrom);
      if (idx == -1) return null;
      final closeIdx = text.indexOf(close, idx + open.length);
      if (closeIdx != -1 && closeIdx >= cursor) {
        return [idx, idx + open.length, closeIdx, closeIdx + close.length];
      }
      searchFrom = idx - 1;
    }
    return null;
  }

  /// Split an enclosing style around a range.
  List<Object>? _splitEnclosingStyle(
      String text, int selStart, int selEnd, String open, String close) {
    final pair =
        _findEnclosingPair(text, (selStart + selEnd) ~/ 2, open, close);
    if (pair == null) return null;
    final oStart = pair[0], oEnd = pair[1], cStart = pair[2], cEnd = pair[3];

    if (selStart <= oEnd && selEnd >= cStart) return null;

    final before = text.substring(oEnd, selStart);
    final selected = text.substring(selStart, selEnd);
    final after = text.substring(selEnd, cStart);

    final buf = StringBuffer();
    buf.write(text.substring(0, oStart));
    if (before.isNotEmpty) {
      buf.write(open);
      buf.write(before);
      buf.write(close);
    }
    final newSelStart = buf.length;
    buf.write(selected);
    final newSelEnd = buf.length;
    if (after.isNotEmpty) {
      buf.write(open);
      buf.write(after);
      buf.write(close);
    }
    buf.write(text.substring(cEnd));
    return [buf.toString(), newSelStart, newSelEnd];
  }
}
