part of 'teleprompter_screen.dart';

extension _PresenterHotkeyParts on _TeleprompterScreenState {
  bool get _presenterHotkeysAvailable {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        _searchDialogOpen ||
        _closingPresentation ||
        _presenterWalkthroughVisible) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus?.widget is! EditableText &&
        focus?.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  bool _handlePresentationKey(KeyEvent event) {
    if (!_presenterHotkeysAvailable ||
        event is! KeyDownEvent ||
        event.synthesized) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _presenterFullscreen &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isShiftPressed) {
      unawaited(_setPresenterFullscreen(false));
      return true;
    }
    final action = ref.read(hotkeyProvider).actionFor(event);
    if (action == null) return false;
    switch (action) {
      case AppHotkeyAction.enterFullscreen:
        unawaited(_setPresenterFullscreen(true));
      case AppHotkeyAction.exitFullscreen:
        unawaited(_setPresenterFullscreen(false));
      case AppHotkeyAction.searchScript:
        unawaited(_showSearchDialog());
      case AppHotkeyAction.previousBookmark:
      case AppHotkeyAction.nextBookmark:
      case AppHotkeyAction.toggleBookmark:
        if (_bookmarkHotkeyBusy || _bookmarkLoadingKey != null) return true;
        final script = ref.read(scriptProvider);
        if (script == null || script.isEmpty) return true;
        final position = ref.read(teleprompterProvider).confirmedWordIndex;
        _bookmarkHotkeyBusy = true;
        unawaited(_runPresenterBookmarkHotkey(action, script, position));
    }
    return true;
  }

  Future<void> _runPresenterBookmarkHotkey(
    AppHotkeyAction action,
    Script script,
    int position,
  ) async {
    bool stillCurrent() =>
        _presenterHotkeysAvailable &&
        identical(ref.read(scriptProvider), script);
    try {
      if (!await _ensurePresenterBookmarkAccess() || !stillCurrent()) return;
      if (action == AppHotkeyAction.previousBookmark ||
          action == AppHotkeyAction.nextBookmark) {
        await _jumpPresenterBookmark(
          action == AppHotkeyAction.nextBookmark ? 1 : -1,
          fromWordIndex: position,
          stillCurrent: stillCurrent,
        );
        return;
      }
      final index = ScriptBookmarkService.nearestBookmarkableWordIndex(
        script.words,
        position,
      );
      if (index == null) return;
      await _loadBookmarksForScript(script, force: true);
      if (!mounted || !stillCurrent()) return;
      if (_bookmarks.any((bookmark) => bookmark.wordIndex == index)) {
        await _deletePresenterBookmark(index, stillCurrent: stillCurrent);
      } else {
        await _addPresenterBookmark(
          atWordIndex: index,
          stillCurrent: stillCurrent,
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'presenter.bookmarkHotkey',
      );
      if (mounted && stillCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update the bookmark. Please try again.'),
          ),
        );
      }
    } finally {
      _bookmarkHotkeyBusy = false;
    }
  }
}
