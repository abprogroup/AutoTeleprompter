part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardBookmarkParts on _ScriptEditorScreenState {
  int? _rawOffsetAfterLeadingVisibleBookmark(String text) {
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty || visible[0] != _keyboardBookmarkSign) return null;
    return MarkupController.visualToRawOffset(
      text,
      1,
    ).clamp(0, text.length).toInt();
  }

  int _firstKeyboardVisibleRawOffset(String text) {
    var offset = 0;
    final firstMarkupVisible = MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
    if (firstMarkupVisible > offset) offset = firstMarkupVisible;

    final afterBookmarkCluster = _firstRawOffsetAfterLeadingBookmarkCluster(
      text,
    );
    if (afterBookmarkCluster > offset) offset = afterBookmarkCluster;
    return offset;
  }

  int _blockEntryStartRawOffset(String text) {
    if (text.isEmpty) return 0;
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty) return 0;
    return MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
  }

  bool _visibleTextAfterLeadingBookmarkClusterIsEmpty(String text) {
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty || visible[0] != _keyboardBookmarkSign) return false;
    var index = 0;
    while (index < visible.length && visible[index] == _keyboardBookmarkSign) {
      index++;
    }
    return visible.substring(index).trim().isEmpty;
  }

  int _firstRawOffsetAfterLeadingBookmarkCluster(String text) {
    var offset = 0;
    var moved = true;
    var sawBookmark = false;
    while (moved && offset < text.length) {
      moved = false;
      while (offset < text.length && text[offset] == _keyboardBookmarkSign) {
        offset++;
        moved = true;
        sawBookmark = true;
      }
      if (sawBookmark) {
        while (offset < text.length &&
            (text.codeUnitAt(offset) == 0x0A ||
                text.codeUnitAt(offset) == 0x0D)) {
          offset++;
          moved = true;
        }
      }
      final tagMatch = MarkupDecorationParser.tagRegex.matchAsPrefix(
        text,
        offset,
      );
      if (tagMatch != null && tagMatch.start == offset) {
        offset = tagMatch.end;
        moved = true;
      }
    }
    return offset;
  }
}
