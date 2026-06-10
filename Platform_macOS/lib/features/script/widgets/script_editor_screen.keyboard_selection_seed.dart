part of 'script_editor_screen.dart';

extension _ScriptEditorKeyboardSelectionSeedParts on _ScriptEditorScreenState {
  ({
    SelectionEndpoint anchor,
    SelectionEndpoint focus,
    String seedSource,
    bool staleOverlayRejected,
  })? _shiftSelectionSeed() {
    final controller = _lastFocusedController ?? _activeController;
    final overlayHasSelection = _overlayKey.currentState?.hasSelection ?? false;
    final visibleOverlayRange = _hasVisibleAppSelectionRange();
    final session = _overlayKey.currentState?.selectionSessionSnapshot;

    if (controller == null) {
      if (overlayHasSelection && session != null) {
        _shiftSelectionAnchor = session.anchor;
        _shiftSelectionFocus = session.focus;
        return (
          anchor: session.anchor,
          focus: session.focus,
          seedSource: 'overlay-no-native-focus',
          staleOverlayRejected: false,
        );
      }
      return null;
    }

    final block = _controllers.indexOf(controller);
    if (block < 0) return null;
    final selection = controller.selection.isValid
        ? controller.selection
        : const TextSelection.collapsed(offset: 0);
    final realAnchor = SelectionEndpoint(
      block: block,
      offset: selection.baseOffset.clamp(0, controller.text.length).toInt(),
    );
    final realFocus = SelectionEndpoint(
      block: block,
      offset: selection.extentOffset.clamp(0, controller.text.length).toInt(),
    );

    if (session != null &&
        overlayHasSelection &&
        _overlaySessionOwnsShiftContinuation(session)) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay-app-session',
        staleOverlayRejected: false,
      );
    }

    if (session != null &&
        overlayHasSelection &&
        _nativeSelectionContinuesOverlaySession(
          session: session,
          nativeAnchor: realAnchor,
          nativeFocus: realFocus,
          isNativeCollapsed: selection.isCollapsed,
        )) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay',
        staleOverlayRejected: false,
      );
    }
    if (session != null && overlayHasSelection && !selection.isCollapsed) {
      _shiftSelectionAnchor = session.anchor;
      _shiftSelectionFocus = session.focus;
      return (
        anchor: session.anchor,
        focus: session.focus,
        seedSource: 'overlay-over-native-range',
        staleOverlayRejected: false,
      );
    }

    final rememberedAnchor = _shiftSelectionAnchor;
    final rememberedFocus = _shiftSelectionFocus;
    if (rememberedAnchor != null &&
        rememberedFocus != null &&
        _sameEndpoint(rememberedFocus, realFocus)) {
      return (
        anchor: rememberedAnchor,
        focus: rememberedFocus,
        seedSource: visibleOverlayRange
            ? 'remembered-overlay'
            : 'remembered-collapsed-shift',
        staleOverlayRejected: false,
      );
    }

    var staleOverlayRejected = false;
    if (overlayHasSelection || visibleOverlayRange || _isGlobalSelection) {
      staleOverlayRejected = true;
      _clearSelectionForNativeShiftSeed(
        reason: 'staleOverlayRejected before shift seed',
      );
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    return (
      anchor: realAnchor,
      focus: realFocus,
      seedSource: selection.isCollapsed ? 'native-caret' : 'native-range',
      staleOverlayRejected: staleOverlayRejected,
    );
  }

  bool _overlaySessionOwnsShiftContinuation(
    SelectionSessionSnapshot session,
  ) {
    return session.mode == SelectionSessionMode.overlaySelection ||
        session.mode == SelectionSessionMode.handleDrag;
  }

  bool _nativeSelectionContinuesOverlaySession({
    required SelectionSessionSnapshot session,
    required SelectionEndpoint nativeAnchor,
    required SelectionEndpoint nativeFocus,
    required bool isNativeCollapsed,
  }) {
    if (isNativeCollapsed) {
      return _sameEndpoint(nativeFocus, session.focus);
    }
    if (_sameEndpoint(nativeAnchor, session.anchor) &&
        _sameEndpoint(nativeFocus, session.focus)) {
      return true;
    }
    return _sameEndpoint(nativeAnchor, session.focus) &&
        _sameEndpoint(nativeFocus, session.anchor);
  }

  void _clearSelectionForNativeShiftSeed({required String reason}) {
    _overlayKey.currentState?.clearSelection();
    for (final c in _controllers) {
      c.isGlobalSelected = false;
      c.externalSelection = null;
      c.externalVisibleSelection = null;
      c.refresh();
    }
    _shiftSelectionAnchor = null;
    _shiftSelectionFocus = null;
    // ignore: invalid_use_of_protected_member
    _setEditorState(() {
      _isGlobalSelection = false;
      _lastArrowDecision = reason;
    });
  }
}
