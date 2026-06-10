part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardBookmarkHelpers on _ScriptEditorScreenState {
  ({int block, int offset})? _leadingHiddenPrefixPlainHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool isRtl,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    if (text.isEmpty) return null;

    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final firstVisibleRaw = _firstKeyboardVisibleRawOffset(text);
    if (firstVisibleRaw <= 0 || safeRaw >= firstVisibleRaw) return null;

    final enterKey =
        isRtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    if (key == enterKey) {
      final afterVisibleBookmark = _rawOffsetAfterLeadingVisibleBookmark(text);
      if (afterVisibleBookmark != null) {
        if (safeRaw < afterVisibleBookmark) {
          final targetRaw = firstVisibleRaw > afterVisibleBookmark
              ? firstVisibleRaw
              : afterVisibleBookmark;
          return (block: blockIndex, offset: targetRaw);
        }
        if (safeRaw < firstVisibleRaw) {
          return (block: blockIndex, offset: firstVisibleRaw);
        }
        if (_visibleTextAfterLeadingBookmarkClusterIsEmpty(text)) {
          if (blockIndex >= _controllers.length - 1) {
            return (block: blockIndex, offset: afterVisibleBookmark);
          }
          return (block: blockIndex + 1, offset: 0);
        }
      }
      final targetRaw = firstVisibleRaw;
      if (targetRaw >= text.length) {
        if (blockIndex >= _controllers.length - 1) return null;
        return (block: blockIndex + 1, offset: 0);
      }
      return (block: blockIndex, offset: targetRaw);
    }

    final exitKey =
        isRtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;
    if (key == exitKey && safeRaw <= 0 && blockIndex > 0) {
      return (
        block: blockIndex - 1,
        offset: MarkupController.safeEndOffset(
          _controllers[blockIndex - 1].text,
        ),
      );
    }
    return null;
  }

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

  int? _ltrHiddenPrefixVisibleStep({
    required String text,
    required int rawOffset,
    required LogicalKeyboardKey key,
  }) {
    if (key != LogicalKeyboardKey.arrowRight || text.isEmpty) return null;
    final visible = EditorTextGeometryService.visibleText(text);
    if (visible.isEmpty) return null;
    final firstVisibleRaw = MarkupController.visualToRawOffset(
      text,
      0,
    ).clamp(0, text.length).toInt();
    if (firstVisibleRaw <= 0) return null;
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    if (safeRaw < firstVisibleRaw) return firstVisibleRaw;
    final visibleOffset = MarkupController.rawToVisualOffset(
      text,
      safeRaw,
    ).clamp(0, visible.length).toInt();
    if (safeRaw == firstVisibleRaw && visibleOffset == 0) {
      return MarkupController.visualToRawOffset(
        text,
        1,
      ).clamp(0, text.length).toInt();
    }
    return null;
  }

  ({int block, int offset})? _leadingBookmarkPlainHorizontalTarget({
    required int blockIndex,
    required int rawOffset,
    required LogicalKeyboardKey key,
    required bool isRtl,
  }) {
    if (blockIndex < 0 || blockIndex >= _controllers.length) return null;
    final text = _controllers[blockIndex].text;
    final afterVisibleBookmark = _rawOffsetAfterLeadingVisibleBookmark(text);
    if (afterVisibleBookmark == null) return null;
    final safeRaw = rawOffset.clamp(0, text.length).toInt();
    final afterLeadingBookmarks = _firstRawOffsetAfterLeadingBookmarkCluster(
      text,
    );
    final enterKey =
        isRtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
    final exitKey =
        isRtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft;

    if (key == enterKey) {
      if (safeRaw < afterVisibleBookmark) {
        final targetRaw = afterLeadingBookmarks > afterVisibleBookmark
            ? afterLeadingBookmarks
            : afterVisibleBookmark;
        return (block: blockIndex, offset: targetRaw);
      }
      if (_visibleTextAfterLeadingBookmarkClusterIsEmpty(text)) {
        if (blockIndex < _controllers.length - 1) {
          return (block: blockIndex + 1, offset: 0);
        }
        return (block: blockIndex, offset: afterVisibleBookmark);
      }
      if (afterLeadingBookmarks >= text.length &&
          safeRaw >= afterLeadingBookmarks &&
          blockIndex < _controllers.length - 1) {
        return (block: blockIndex + 1, offset: 0);
      }
      if (safeRaw >= afterLeadingBookmarks) return null;
      if (afterLeadingBookmarks >= text.length &&
          blockIndex < _controllers.length - 1) {
        return (block: blockIndex + 1, offset: 0);
      }
      return (block: blockIndex, offset: afterLeadingBookmarks);
    }
    if (key == exitKey &&
        safeRaw > afterVisibleBookmark &&
        safeRaw <= afterLeadingBookmarks) {
      return (block: blockIndex, offset: afterVisibleBookmark);
    }
    if (key == exitKey && safeRaw > 0 && safeRaw <= afterVisibleBookmark) {
      return (block: blockIndex, offset: 0);
    }
    return null;
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
