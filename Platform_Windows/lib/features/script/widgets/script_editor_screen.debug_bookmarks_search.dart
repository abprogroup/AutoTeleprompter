part of 'script_editor_screen.dart';

extension _ScriptEditorDebugBookmarkSearchParts on _ScriptEditorScreenState {
  Widget _buildDebugSentry() {
    final activeIdx = _focusNodes.indexWhere((n) => n.hasFocus);
    final sel = _activeController?.selection;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 4, spreadRadius: 1)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚙️ EDITOR SENTRY',
              style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text('Blocks: ${_controllers.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Active Block: ${activeIdx != -1 ? activeIdx : "None"}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          if (sel != null)
            Text('Cursor: [${sel.baseOffset}, ${sel.extentOffset}]',
                style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('Global Selection: $_isGlobalSelection',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
          Text('History States: ${_history.length}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }

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

  int _wordIndexForEditorPosition(int block, int offset) {
    final textBefore = StringBuffer();
    for (var i = 0; i < block && i < _controllers.length; i++) {
      if (textBefore.isNotEmpty) textBefore.write('\n');
      textBefore.write(_controllers[i].text);
    }
    if (block >= 0 && block < _controllers.length) {
      if (textBefore.isNotEmpty) textBefore.write('\n');
      textBefore.write(
        _controllers[block]
            .text
            .substring(0, offset.clamp(0, _controllers[block].text.length)),
      );
    }
    final beforeTokens = WordAligner.tokenize(textBefore.toString());
    final allTokens = WordAligner.tokenize(_getRefinedFullText());
    final maxIndex = allTokens.isEmpty ? 0 : allTokens.length - 1;
    return beforeTokens.length.clamp(0, maxIndex).toInt();
  }

  String _bookmarkLabelForEditorPosition(int block, int offset) {
    if (block < 0 || block >= _controllers.length) return 'Bookmark';
    final text = StylingService.stripTags(_controllers[block].text)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return 'Block ${block + 1}';
    return text.length <= 44 ? text : '${text.substring(0, 44)}...';
  }

  Future<void> _addEditorBookmark() async {
    if (_controllers.isEmpty) return;
    await _loadBookmarksForCurrentScript(force: true);
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final bookmark = ScriptBookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: _bookmarkLabelForEditorPosition(block, offset),
      wordIndex: _wordIndexForEditorPosition(block, offset),
      blockIndex: block,
      offset: offset,
      createdAt: DateTime.now(),
    );
    setState(() {
      _bookmarks = ScriptBookmarkService.upsert(_bookmarks, bookmark);
    });
    await _saveBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark saved: ${bookmark.label}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _jumpEditorBookmark(int direction) async {
    await _loadBookmarksForCurrentScript(force: true);
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
      return (
        block: bookmark.blockIndex,
        offset: bookmark.offset.clamp(
          0,
          _controllers[bookmark.blockIndex].text.length,
        )
      );
    }

    var runningTokens = 0;
    for (var block = 0; block < _controllers.length; block++) {
      final blockTokens = WordAligner.tokenize(_controllers[block].text);
      if (bookmark.wordIndex < runningTokens + blockTokens.length) {
        final localToken = (bookmark.wordIndex - runningTokens)
            .clamp(0, blockTokens.isEmpty ? 0 : blockTokens.length - 1)
            .toInt();
        return (
          block: block,
          offset: _rawOffsetForTokenIndex(_controllers[block].text, localToken)
        );
      }
      runningTokens += blockTokens.length + 1;
    }
    final last = _controllers.isEmpty ? -1 : _controllers.length - 1;
    return (
      block: last,
      offset: last >= 0 && last < _controllers.length
          ? _controllers[last].text.length
          : 0
    );
  }

  int _rawOffsetForTokenIndex(String text, int tokenIndex) {
    final matches = RegExp(r'\S+').allMatches(text).toList();
    if (matches.isEmpty) return 0;
    final target = tokenIndex.clamp(0, matches.length - 1).toInt();
    return matches[target].start;
  }

  void _goToEditorBookmark(int bookmarkIndex) {
    if (bookmarkIndex < 0 || bookmarkIndex >= _bookmarks.length) return;
    final bookmark = _bookmarks[bookmarkIndex];
    final position = _editorPositionForBookmark(bookmark);
    if (position.block < 0 || position.block >= _controllers.length) return;
    final controller = _controllers[position.block];
    final selection = TextSelection.collapsed(offset: position.offset);
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.externalSelection = null;
      c.isGlobalSelected = false;
    }
    controller.selection = selection;
    _lastFocusedController = controller;
    setState(() {
      _isGlobalSelection = false;
    });
    _focusNodes[position.block].requestFocus();
    _scrollEditorBlockIntoView(position.block, alignment: 0.28);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bookmark: ${bookmark.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _hasBookmarkInEditorBlock(int block) {
    return _bookmarks.any((bookmark) {
      final position = _editorPositionForBookmark(bookmark);
      return position.block == block;
    });
  }

  Future<void> _deleteEditorBookmarkAtCurrentPosition() async {
    await _loadBookmarksForCurrentScript(force: true);
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
    final ids = _bookmarks
        .where(
            (bookmark) => _editorPositionForBookmark(bookmark).block == block)
        .map((bookmark) => bookmark.id)
        .toSet();
    await _deleteEditorBookmarkIds(ids);
  }

  Future<void> _deleteEditorBookmarkIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final before = _bookmarks.length;
    final next =
        _bookmarks.where((bookmark) => !ids.contains(bookmark.id)).toList();
    final deleted = before - next.length;
    if (deleted <= 0) return;
    setState(() => _bookmarks = next);
    await _saveBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            deleted == 1 ? 'Bookmark deleted' : '$deleted bookmarks deleted'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) => ensure());
  }

  void _onCopyClean() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      final plainBuf = StringBuffer();
      final htmlBuf = StringBuffer();
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        String slice;
        if (c.isGlobalSelected || (sel != null && sel.isValid && !sel.isCollapsed)) {
          if (c.isGlobalSelected || sel == null || !sel.isValid) {
            slice = c.text;
          } else {
            slice = c.text.substring(sel.start, sel.end);
          }
          if (slice.isEmpty) continue;
          if (plainBuf.isNotEmpty) plainBuf.write('\n');
          plainBuf.write(StylingService.stripTags(slice));
          htmlBuf.write(StylingService.markupToHtml(slice));
        }
      }
      if (plainBuf.isEmpty) return;
      RichClipboard.setHtml(
          plain: plainBuf.toString(), html: htmlBuf.toString());
      return;
    }
    final controller = _activeController;
    if (controller == null) return;
    final slice = controller.selection.textInside(controller.text);
    if (slice.isEmpty) return;
    RichClipboard.setHtml(
      plain: StylingService.stripTags(slice),
      html: StylingService.markupToHtml(slice),
    );
  }

  void _onCut() {
    _onCopyClean();
    _deleteSelection();
  }

  void _deleteSelection() {
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection || hasOverlay) {
      setState(() => _isCommandExecuting = true);
      final List<int> toRemove = [];
      for (int i = 0; i < _controllers.length; i++) {
        final c = _controllers[i];
        final sel = c.externalSelection;
        if (c.isGlobalSelected) {
          toRemove.add(i);
        } else if (sel != null && sel.isValid && !sel.isCollapsed) {
          final before = c.text.substring(0, sel.start);
          final after = c.text.substring(sel.end);
          c.text = before + after;
          c.externalSelection = null;
          c.refresh();
        }
      }
      // Remove blocks that were fully selected
      if (toRemove.isNotEmpty && _controllers.length > toRemove.length) {
        for (final idx in toRemove.reversed) {
          _removeBlock(idx);
        }
      } else if (toRemove.length == _controllers.length) {
        // Clear all but first
        for (int i = _controllers.length - 1; i > 0; i--) _removeBlock(i);
        _controllers.first.clear();
        _controllers.first.refresh();
      }
      _clearGlobalSelection();
      setState(() => _isCommandExecuting = false);
      _saveHistory(description: 'Delete Selection');
    } else {
      final c = _activeController;
      if (c != null && !c.selection.isCollapsed) {
        final sel = c.selection;
        final before = c.text.substring(0, sel.start);
        final after = c.text.substring(sel.end);
        c.value = TextEditingValue(
          text: before + after,
          selection: TextSelection.collapsed(offset: sel.start),
        );
        _saveHistory(description: 'Delete');
      }
    }
  }

  Future<void> _onPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final text = data!.text!;

    // 1. Delete selection if any
    final hasOverlay = _overlayKey.currentState?.hasSelection ?? false;
    if (_isGlobalSelection ||
        hasOverlay ||
        (_activeController != null && !_activeController!.selection.isCollapsed)) {
      _deleteSelection();
    }

    // 2. Insert text
    final c = _activeController;
    if (c != null) {
      final sel = c.selection;
      final oldText = c.text;
      final before = oldText.substring(0, sel.start);
      final after = oldText.substring(sel.end);

      if (text.contains('\n')) {
        // Multi-line paste: split into blocks
        final lines = text.split('\n');
        final currentIdx = _controllers.indexOf(c);
        if (currentIdx != -1) {
          setState(() {
            // Update first block
            c.text = before + lines[0];
            // Insert intermediate blocks
            for (int i = 1; i < lines.length - 1; i++) {
              _addBlock(currentIdx + i, text: lines[i]);
            }
            // Insert last block with remainder of original block
            final lastLine = lines.last + after;
            _addBlock(currentIdx + lines.length - 1, text: lastLine);

            // Focus end of paste
            final targetIdx = currentIdx + lines.length - 1;
            Future.delayed(Duration.zero, () {
              if (mounted) {
                _focusNodes[targetIdx].requestFocus();
                _controllers[targetIdx].selection =
                    TextSelection.collapsed(offset: lines.last.length);
              }
            });
          });
        }
      } else {
        c.value = TextEditingValue(
          text: before + text + after,
          selection: TextSelection.collapsed(offset: sel.start + text.length),
        );
      }
      _saveHistory(description: 'Paste');
    }
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: _lastSearchQuery);
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Search script', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Word to find',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFFBF00))),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBF00),
                foregroundColor: Colors.black),
            child: const Text('Find'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (query == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _lastSearchQuery = trimmed;
    _findInEditor(trimmed);
  }

  void _findInEditor(String query) {
    if (_controllers.isEmpty) return;
    final needle = query.toLowerCase();
    final activeIndex = _activeController != null
        ? _controllers.indexOf(_activeController!)
        : 0;
    final startBlock = activeIndex < 0 ? 0 : activeIndex;
    final activeSelection = _controllers[startBlock].selection;
    final startOffset = activeSelection.isValid
        ? activeSelection.end.clamp(0, _controllers[startBlock].text.length)
        : 0;

    ({int block, int visualOffset})? match;
    for (var i = startBlock; i < _controllers.length; i++) {
      final rawText = _controllers[i].text;
      final fromRaw = i == startBlock ? startOffset : 0;
      final fromVisual = MarkupController.rawToVisualOffset(rawText, fromRaw);
      final idx = _visibleSearchIndex(rawText, needle, fromVisual);
      if (idx >= 0) {
        match = (block: i, visualOffset: idx);
        break;
      }
    }
    if (match == null) {
      for (var i = 0; i <= startBlock && i < _controllers.length; i++) {
        final rawText = _controllers[i].text;
        final endRaw = i == startBlock ? startOffset : rawText.length;
        final endVisual = MarkupController.rawToVisualOffset(rawText, endRaw);
        final idx = _visibleSearchIndex(rawText, needle, 0,
            endVisualExclusive: endVisual);
        if (idx >= 0) {
          match = (block: i, visualOffset: idx);
          break;
        }
      }
    }

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No match for "$query"'),
          backgroundColor: Colors.black.withOpacity(0.9),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final ctrl in _controllers) {
      ctrl.isGlobalSelected = false;
      ctrl.externalSelection = null;
    }
    final c = _controllers[match.block];
    final rawStart =
        MarkupController.visualToRawOffset(c.text, match.visualOffset);
    final rawEnd = MarkupController.visualToRawOffset(
      c.text,
      match.visualOffset + query.length,
    ).clamp(rawStart, c.text.length);
    final selection = TextSelection(
      baseOffset: rawStart,
      extentOffset: rawEnd,
    );
    c.externalSelection = selection;
    c.selection = selection;
    _lastFocusedController = c;
    _focusNodes[match.block].requestFocus();
    c.refresh();
    setState(() {});
    _scrollEditorBlockIntoView(match.block, alignment: 0.25);
  }

  int _visibleSearchIndex(String rawText, String needle, int startVisual,
      {int? endVisualExclusive}) {
    final visible = StylingService.stripTags(rawText).toLowerCase();
    final start = startVisual.clamp(0, visible.length).toInt();
    final end = (endVisualExclusive ?? visible.length)
        .clamp(start, visible.length)
        .toInt();
    return visible.substring(0, end).indexOf(needle, start);
  }

  void _selectAllBlocks() {
    _overlayKey.currentState?.selectAll();
    _isGlobalSelection = true;
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    // Refresh after setState so TextFields repaint with new flags.
    for (final c in _controllers) {
      c.refresh();
    }
  }

  void _clearGlobalSelection() {
    _overlayKey.currentState?.clearSelection();
    _isGlobalSelection = false;
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      // Collapse native selection to prevent residual highlight in buildTextSpan.
      // For RTL text, use baseOffset (cursor stays at visual tap position).
      if (!c.selection.isCollapsed) {
        final collapseAt = c.selection.baseOffset.clamp(0, c.text.length);
        c.selection = TextSelection.collapsed(offset: collapseAt);
      }
    }
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
    // Safety net: re-clear after Flutter's TextField processes the tap gesture,
    // which can re-establish selection in RTL blocks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      bool needsRefresh = false;
      for (final c in _controllers) {
        if (c.externalSelection != null) {
          c.externalSelection = null;
          needsRefresh = true;
        }
        if (c.isGlobalSelected) {
          c.isGlobalSelected = false;
          needsRefresh = true;
        }
      }
      if (needsRefresh) {
        for (final c in _controllers) {
          c.refresh();
        }
        setState(() {});
      }
    });
  }

  /// Re-sync externalSelection after a global style operation changes text lengths.
  void _resyncGlobalSelection() {
    // If the overlay has a selection, refresh its boundaries so handles don't stay
    // at the pre-tag-insertion character offsets which are now mid-sentence.
    if (_overlayKey.currentState?.hasSelection ?? false) {
      _overlayKey.currentState?.selectAll();
    }
    for (final c in _controllers) {
      c.isGlobalSelected = true;
      c.externalSelection =
          TextSelection(baseOffset: 0, extentOffset: c.text.length);
    }
    setState(() {});
    for (final c in _controllers) {
      c.refresh();
    }
  }
}
