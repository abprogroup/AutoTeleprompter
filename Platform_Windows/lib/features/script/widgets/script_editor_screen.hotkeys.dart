part of 'script_editor_screen.dart';

extension _ScriptEditorHotkeyParts on _ScriptEditorScreenState {
  bool get _editorAppHotkeysAvailable =>
      mounted &&
      ModalRoute.of(context)?.isCurrent != false &&
      !_searchDialogOpen &&
      !_walkthroughSampleGuideVisible &&
      !_isPendingLoad &&
      !_isLoading &&
      !_isBulkLoadingBlocks &&
      !_isCommandExecuting &&
      !(_overlayKey.currentState?.isHandleInteractionActive ?? false);

  bool get _foreignEditorInputHasFocus {
    if (_focusNodes.any((node) => node.hasFocus)) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.widget is EditableText ||
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleEditorAppHotkey(KeyEvent event) {
    if (!_editorAppHotkeysAvailable || _foreignEditorInputHasFocus) {
      return false;
    }
    final editingText =
        _focusNodes.any((node) => node.hasFocus) ||
        _hasVisibleAppSelectionRange() ||
        (_overlayKey.currentState?.hasSelection ?? false);
    final action = ref
        .read(hotkeyProvider)
        .actionFor(event, editingText: editingText);
    if (action == null ||
        action == AppHotkeyAction.enterFullscreen ||
        action == AppHotkeyAction.exitFullscreen) {
      return false;
    }
    if (action == AppHotkeyAction.searchScript) {
      unawaited(_showEditorSearchDialog());
      return true;
    }
    // One in-flight command owns this anchor. A repeated press cannot race its
    // encrypted load/save, and changing routes/caret/text invalidates the work.
    if (_editorBookmarkHotkeyBusy || _bookmarkLoadingKey != null) return true;
    final block = _currentEditorBlockIndex();
    if (block < 0 || block >= _controllers.length) return true;
    final controller = _controllers[block];
    final selection = controller.selection;
    if (action == AppHotkeyAction.toggleBookmark &&
        (!selection.isValid ||
            !selection.isCollapsed ||
            _hasVisibleAppSelectionRange() ||
            (_overlayKey.currentState?.hasSelection ?? false))) {
      return true;
    }
    final sessionId = _currentSessionId;
    final title = _currentTitle;
    final text = controller.text;
    bool stillCurrent() =>
        _editorAppHotkeysAvailable &&
        !_foreignEditorInputHasFocus &&
        _currentSessionId == sessionId &&
        _currentTitle == title &&
        block < _controllers.length &&
        identical(_controllers[block], controller) &&
        identical(_activeController, controller) &&
        controller.text == text &&
        controller.selection == selection;
    _editorBookmarkHotkeyBusy = true;
    unawaited(_runEditorBookmarkHotkey(action, stillCurrent));
    return true;
  }

  Future<void> _runEditorBookmarkHotkey(
    AppHotkeyAction action,
    bool Function() stillCurrent,
  ) async {
    try {
      if (!await _ensureEditorPremiumAccess('Bookmarks') || !stillCurrent()) {
        return;
      }
      switch (action) {
        case AppHotkeyAction.previousBookmark:
          await _jumpEditorBookmark(-1, stillCurrent: stillCurrent);
        case AppHotkeyAction.nextBookmark:
          await _jumpEditorBookmark(1, stillCurrent: stillCurrent);
        case AppHotkeyAction.toggleBookmark:
          await _toggleEditorBookmark(stillCurrent);
        default:
          break;
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'scriptEditor.bookmarkHotkey',
      );
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update the bookmark. Try again.'),
          ),
        );
      }
    } finally {
      _editorBookmarkHotkeyBusy = false;
    }
  }

  Future<void> _toggleEditorBookmark(bool Function() stillCurrent) async {
    if (!stillCurrent()) return;
    final block = _currentEditorBlockIndex();
    final offset = _currentEditorOffset(block);
    final text = _controllers[block].text;
    final signOffset =
        offset < text.length && text[offset] == _bookmarkSign
            ? offset
            : offset > 0 && text[offset - 1] == _bookmarkSign
            ? offset - 1
            : null;
    if (signOffset == null) {
      await _addEditorBookmark(stillCurrent: stillCurrent);
      return;
    }
    // Text-flow signs remain authoritative. Never delete an unrelated nearby
    // bookmark merely because it happens to share the current paragraph.
    await _syncBookmarksFromEditorSigns(notify: false, save: false);
    if (!stillCurrent()) return;
    final ids =
        _bookmarks
            .where(
              (bookmark) =>
                  bookmark.blockIndex == block && bookmark.offset == signOffset,
            )
            .map((bookmark) => bookmark.id)
            .toSet();
    await _deleteEditorBookmarkIds(ids);
  }
}
