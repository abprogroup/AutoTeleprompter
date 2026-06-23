part of 'script_editor_screen.dart';

extension _ScriptEditorBookmarkNavigationParts on _ScriptEditorScreenState {
  // Cursor helpers.

  int _currentEditorBlockIndex() {
    final active = _activeController;
    final index = active == null ? -1 : _controllers.indexOf(active);
    return index >= 0 ? index : 0;
  }

  int _currentEditorOffset(int block) {
    if (block < 0 || block >= _controllers.length) return 0;
    final selection = _controllers[block].selection;
    return selection.isValid
        ? selection.baseOffset.clamp(0, _controllers[block].text.length)
        : 0;
  }

  // Word-index helpers (bookmark-sign aware).

  int _wordIndexForEditorPosition(int block, int offset) {
    final allTokens = WordAligner.tokenize(
      _getRefinedFullTextWithoutBookmarkSigns(),
    );
    if (allTokens.isEmpty) return 0;
    final estimated = _tokenCursorForEditorPosition(block, offset);
    return _snapToReadableWordIndex(allTokens, estimated);
  }

  int _tokenCursorForEditorPosition(int block, int offset) {
    var cursor = 0;
    final lastBlock = _controllers.length - 1;
    for (var i = 0; i < block && i < _controllers.length; i++) {
      cursor += _tokenLengthForEditorBlock(i, includeSoftBreak: i < lastBlock);
    }
    if (block < 0 || block >= _controllers.length) return cursor;
    final text = _controllers[block].text;
    if (text.trim().isEmpty) return cursor;
    final safeOffset = offset.clamp(0, text.length).toInt();
    final localWord = _localWordIndexForRawOffset(text, safeOffset);
    return cursor + localWord;
  }

  int _tokenLengthForEditorBlock(int block, {required bool includeSoftBreak}) {
    if (block < 0 || block >= _controllers.length) return 0;
    final text = _stripBookmarkSigns(_controllers[block].text);
    if (text.trim().isEmpty) return 1;
    final wordCount =
        WordAligner.tokenize(text).where((word) => !word.isNewline).length;
    return wordCount + (includeSoftBreak ? 1 : 0);
  }

  int _localWordIndexForRawOffset(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length).toInt();
    final signsBefore = RegExp(RegExp.escape(_bookmarkSign))
        .allMatches(text.substring(0, safeOffset))
        .length;
    final cleanText = _stripBookmarkSigns(text);
    final cleanOffset =
        (safeOffset - signsBefore).clamp(0, cleanText.length).toInt();
    final visibleText = StylingService.stripTags(cleanText);
    final visibleOffset =
        MarkupController.rawToVisualOffset(cleanText, cleanOffset)
            .clamp(0, visibleText.length)
            .toInt();
    final matches = RegExp(r'\S+').allMatches(visibleText).toList();
    if (matches.isEmpty) return 0;
    for (var i = 0; i < matches.length; i++) {
      if (visibleOffset <= matches[i].start) return i;
      if (visibleOffset > matches[i].start && visibleOffset < matches[i].end) {
        return i;
      }
    }
    return matches.length;
  }

  int _snapToReadableWordIndex(List<ScriptWord> words, int estimated) {
    if (words.isEmpty) return 0;
    final start = estimated.clamp(0, words.length - 1).toInt();
    for (var i = start; i < words.length; i++) {
      if (!words[i].isNewline && words[i].normalized.isNotEmpty) return i;
    }
    for (var i = start; i >= 0; i--) {
      if (!words[i].isNewline && words[i].normalized.isNotEmpty) return i;
    }
    return start;
  }

  String _bookmarkLabelForEditorPosition(int block, int offset) {
    if (block < 0 || block >= _controllers.length) return 'Bookmark';
    final text = StylingService.stripTags(
      _stripBookmarkSigns(_controllers[block].text),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'Block ${block + 1}';
    return text.length <= 44 ? text : '${text.substring(0, 44)}...';
  }

  // Add bookmark.

  Future<void> _addEditorBookmark() async {
    if (!await _ensureEditorPremiumAccess('Bookmarks')) return;
    if (_controllers.isEmpty) return;
    await _loadBookmarksForCurrentScript(force: true);
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    if (block < 0 || block >= _controllers.length) return;
    final controller = _controllers[block];
    final safeOffset = offset.clamp(0, controller.text.length).toInt();
    final alreadyAtOffset = safeOffset < controller.text.length &&
        controller.text[safeOffset] == _bookmarkSign;
    final alreadyBeforeOffset =
        safeOffset > 0 && controller.text[safeOffset - 1] == _bookmarkSign;
    // Cursor must end up after the sign we just inserted; when a sign already
    // exists we leave the caret where it was.
    var cursorOffset = safeOffset;
    if (!alreadyAtOffset && !alreadyBeforeOffset) {
      _isCommandExecuting = true;
      controller.value = TextEditingValue(
        text: controller.text.substring(0, safeOffset) +
            _bookmarkSign +
            controller.text.substring(safeOffset),
        selection: TextSelection.collapsed(offset: safeOffset + 1),
      );
      _isCommandExecuting = false;
      _isDirty = false;
      _lastFocusedController = controller;
      cursorOffset = safeOffset + 1;
      _saveHistory(description: 'Add Bookmark');
    }
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    final label = _bookmarkLabelForEditorPosition(block, safeOffset);
    if (!mounted) return;
    // Restore focus + caret to the editable so keyboard navigation continues
    // from the bookmark instead of jumping to the start of the script.
    _focusEditorPosition((block: block, offset: cursorOffset));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark saved: $label'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Navigate bookmarks.

  Future<void> _jumpEditorBookmark(int direction) async {
    if (!await _ensureEditorPremiumAccess('Bookmarks')) return;
    await _loadBookmarksForCurrentScript(force: true);
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final currentWord = _wordIndexForEditorPosition(block, offset);
    int target;
    if (direction >= 0) {
      target = _bookmarks.indexWhere((b) => b.wordIndex > currentWord);
      if (target == -1) target = 0;
    } else {
      target = _bookmarks.lastIndexWhere((b) => b.wordIndex < currentWord);
      if (target == -1) target = _bookmarks.length - 1;
    }
    _goToEditorBookmark(target);
  }

  ({int block, int offset}) _editorPositionForBookmark(
      ScriptBookmark bookmark) {
    if (bookmark.blockIndex >= 0 && bookmark.blockIndex < _controllers.length) {
      final bookmarkedBlock = _controllers[bookmark.blockIndex];
      if (bookmarkedBlock.text.trim().isEmpty) {
        return _editorPositionForWordIndex(bookmark.wordIndex);
      }
      return (
        block: bookmark.blockIndex,
        offset: bookmark.offset.clamp(
          0,
          _controllers[bookmark.blockIndex].text.length,
        )
      );
    }
    return _editorPositionForWordIndex(bookmark.wordIndex);
  }

  ({int block, int offset}) _editorPositionForWordIndex(int wordIndex) {
    var cursor = 0;
    final lastBlock = _controllers.length - 1;
    for (var block = 0; block < _controllers.length; block++) {
      final text = _controllers[block].text;
      final cleanText = _stripBookmarkSigns(text);
      final visibleText = StylingService.stripTags(cleanText);
      final wordMatches = RegExp(r'\S+').allMatches(visibleText).toList();
      if (wordMatches.isNotEmpty &&
          wordIndex >= cursor &&
          wordIndex < cursor + wordMatches.length) {
        final localToken =
            (wordIndex - cursor).clamp(0, wordMatches.length - 1).toInt();
        final cleanRawOffset = MarkupController.visualToRawOffset(
          cleanText,
          wordMatches[localToken].start,
        );
        return (
          block: block,
          offset: _rawOffsetWithBookmarkSigns(text, cleanRawOffset),
        );
      }
      cursor += _tokenLengthForEditorBlock(
        block,
        includeSoftBreak: block < lastBlock,
      );
    }
    final last = _controllers.isEmpty ? -1 : _controllers.length - 1;
    return (
      block: last,
      offset: last >= 0 && last < _controllers.length
          ? _controllers[last].text.length
          : 0
    );
  }

  int _rawOffsetWithBookmarkSigns(String text, int cleanRawOffset) {
    final target =
        cleanRawOffset.clamp(0, _stripBookmarkSigns(text).length).toInt();
    var raw = 0;
    var clean = 0;
    while (raw < text.length && clean < target) {
      if (text.startsWith(_bookmarkSign, raw)) {
        raw += _bookmarkSign.length;
        continue;
      }
      if (text.startsWith(_legacyBookmarkSign, raw)) {
        raw += _legacyBookmarkSign.length;
        continue;
      }
      raw++;
      clean++;
    }
    return raw.clamp(0, text.length).toInt();
  }

  void _focusEditorPosition(({int block, int offset}) position) {
    if (position.block < 0 || position.block >= _controllers.length) return;
    final controller = _controllers[position.block];
    final selection = TextSelection.collapsed(
      offset: position.offset.clamp(0, controller.text.length).toInt(),
    );
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.externalSelection = null;
      c.isGlobalSelected = false;
    }
    controller.selection = selection;
    _lastFocusedController = controller;
    _setEditorState(() => _isGlobalSelection = false);
    _focusNodes[position.block].requestFocus();
    _scrollEditorBlockIntoView(position.block, alignment: 0.28);
  }

  void _focusEditorWordIndex(int wordIndex) {
    _focusEditorPosition(_editorPositionForWordIndex(wordIndex));
  }

  void _goToEditorBookmark(int bookmarkIndex) {
    if (bookmarkIndex < 0 || bookmarkIndex >= _bookmarks.length) return;
    final bookmark = _bookmarks[bookmarkIndex];
    final position = _editorPositionForBookmark(bookmark);
    _focusEditorPosition(position);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _hasBookmarkInEditorBlock(int block) {
    if (block < 0 || block >= _controllers.length) return false;
    return _controllers[block].text.contains(_bookmarkSign);
  }

  // Delete bookmarks.

  Future<void> _deleteEditorBookmarkAtCurrentPosition() async {
    if (!await _ensureEditorPremiumAccess('Bookmarks')) return;
    await _loadBookmarksForCurrentScript(force: true);
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmarks saved for this script yet'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final blockBookmarks = _bookmarks.where((bookmark) {
      final position = _editorPositionForBookmark(bookmark);
      return position.block == block;
    }).toList();
    if (blockBookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No bookmark in the current editor block'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    blockBookmarks.sort((a, b) {
      final aPosition = _editorPositionForBookmark(a);
      final bPosition = _editorPositionForBookmark(b);
      return (aPosition.offset - offset)
          .abs()
          .compareTo((bPosition.offset - offset).abs());
    });
    await _deleteEditorBookmarkIds({blockBookmarks.first.id});
  }

  Future<void> _deleteEditorBookmarksForBlock(int block) async {
    if (!await _ensureEditorPremiumAccess('Bookmarks')) return;
    final ids = _bookmarks
        .where(
            (bookmark) => _editorPositionForBookmark(bookmark).block == block)
        .map((bookmark) => bookmark.id)
        .toSet();
    await _deleteEditorBookmarkIds(ids);
  }

  Future<void> _deleteEditorBookmarkIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final targets =
        _bookmarks.where((bookmark) => ids.contains(bookmark.id)).toList();
    final deleted = targets.length;
    if (deleted <= 0) return;
    _isCommandExecuting = true;
    final ordered = [...targets]..sort((a, b) {
        final aPos = _editorPositionForBookmark(a);
        final bPos = _editorPositionForBookmark(b);
        final blockCompare = bPos.block.compareTo(aPos.block);
        if (blockCompare != 0) return blockCompare;
        return bPos.offset.compareTo(aPos.offset);
      });
    for (final bookmark in ordered) {
      final position = _editorPositionForBookmark(bookmark);
      if (position.block < 0 || position.block >= _controllers.length) continue;
      final controller = _controllers[position.block];
      final offset = position.offset.clamp(0, controller.text.length).toInt();
      var deleteOffset = -1;
      if (offset < controller.text.length &&
          controller.text[offset] == _bookmarkSign) {
        deleteOffset = offset;
      } else if (offset > 0 && controller.text[offset - 1] == _bookmarkSign) {
        deleteOffset = offset - 1;
      }
      if (deleteOffset < 0) continue;
      controller.value = TextEditingValue(
        text: controller.text.substring(0, deleteOffset) +
            controller.text.substring(deleteOffset + _bookmarkSign.length),
        selection: TextSelection.collapsed(offset: deleteOffset),
      );
    }
    _isCommandExecuting = false;
    _isDirty = false;
    _saveHistory(description: 'Delete Bookmark');
    await _syncBookmarksFromEditorSigns(notify: true, save: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            deleted == 1 ? 'Bookmark deleted' : '$deleted bookmarks deleted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Scroll helper shared with search.

  void _scrollEditorBlockIntoView(int block, {double alignment = 0.25}) {
    if (block < 0 || block >= _blockKeys.length) return;
    void ensure({Duration duration = const Duration(milliseconds: 260)}) {
      final ctx = _blockKeys[block].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: alignment,
      );
    }

    final ctx = _blockKeys[block].currentContext;
    if (ctx != null) {
      ensure();
      return;
    }
    final estimatedOffset = _estimatedEditorScrollOffsetForBlock(
      block,
      alignment: alignment,
    );
    if (estimatedOffset == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ensure());
      return;
    }
    unawaited(
      _editorScrollController
          .animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      )
          .then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ensure(duration: const Duration(milliseconds: 80));
        });
      }),
    );
  }

  double? _estimatedEditorScrollOffsetForBlock(
    int block, {
    required double alignment,
  }) {
    if (!_editorScrollController.hasClients) return null;
    final position = _editorScrollController.position;
    final viewportHeight = position.viewportDimension;
    if (viewportHeight <= 0) return null;

    final textWidth = _estimatedEditorTextWidth();
    var blockTop = 24.0; // ListView top padding.
    for (var i = 0; i < block; i++) {
      blockTop += _estimatedEditorBlockHeight(i, textWidth);
    }
    final blockHeight = _estimatedEditorBlockHeight(block, textWidth);
    final target = blockTop - alignment * (viewportHeight - blockHeight);
    return target.clamp(0.0, position.maxScrollExtent).toDouble();
  }

  double _estimatedEditorTextWidth() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final fallbackWidth = MediaQuery.maybeOf(context)?.size.width ?? 800.0;
    final editorWidth = renderBox != null && renderBox.hasSize
        ? renderBox.size.width
        : fallbackWidth;
    final maxWidth = editorWidth > 120.0 ? editorWidth : 120.0;
    return (editorWidth - 48.0 - 30.0).clamp(120.0, maxWidth).toDouble();
  }

  double _estimatedEditorBlockHeight(int block, double textWidth) {
    if (block < 0 || block >= _controllers.length) return 0;
    final controller = _controllers[block];
    final settings = ref.read(settingsProvider);
    final isRtl = _editorBlockResolvedRtl(block);
    final textAlign = EditorTextGeometryService.resolveTextAlign(
      controller.text,
      isRtl: isRtl,
    );
    final style = TextStyle(
      color: Colors.white,
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );
    final maxFontSize = EditorTextGeometryService.maxFontSize(
      controller.text,
      settings.fontSize,
    );
    final span = controller.text.isEmpty
        ? TextSpan(text: ' ', style: style)
        : controller.buildTextSpan(
            context: context,
            style: style,
            withComposing: false,
          );
    final painter = TextPainter(
      text: span,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: textAlign,
      strutStyle: StrutStyle(
        fontSize: maxFontSize,
        height: settings.lineSpacing,
        forceStrutHeight: true,
      ),
    )..layout(maxWidth: textWidth);
    final height = painter.height + 4.0; // TextField vertical content padding.
    final minHeight = maxFontSize * settings.lineSpacing + 4.0;
    final bookmarkHeight = _hasBookmarkInEditorBlock(block) ? 28.0 : 0.0;
    if (height < minHeight) return minHeight;
    if (height < bookmarkHeight) return bookmarkHeight;
    return height;
  }
}
