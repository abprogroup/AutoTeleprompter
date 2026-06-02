part of 'script_editor_screen.dart';

extension _ScriptEditorChromeParts on _ScriptEditorScreenState {
  Widget _buildBottomActions({bool keyboardVisible = false}) {
    const actionHeight = 42.0;
    const actionRadius = 12.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (keyboardVisible && PlatformKeyboard.showDoneBar)
          Container(
            color: const Color(0xFF1C1C1E),
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => FocusScope.of(context).unfocus(),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: actionHeight,
                  child: ElevatedButton.icon(
                    onPressed: _startPresenting,
                    icon:
                        const Icon(Icons.play_circle_filled_rounded, size: 22),
                    label: const Text(
                      'PRESENT',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, actionHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(actionRadius),
                      ),
                      elevation: 12,
                      shadowColor:
                          const Color(0xFFFFBF00).withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Audio only recording',
                child: SizedBox(
                  width: 50,
                  height: actionHeight,
                  child: OutlinedButton(
                    onPressed: _startAudioOnlyContentCreator,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFBF00),
                      side: const BorderSide(color: Color(0xFFFFBF00)),
                      minimumSize: const Size(50, actionHeight),
                      maximumSize: const Size(50, actionHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(actionRadius),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.mic_none_outlined, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Content Creator',
                child: SizedBox(
                  width: 50,
                  height: actionHeight,
                  child: OutlinedButton(
                    onPressed: _startContentCreator,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFFBF00),
                      side: const BorderSide(color: Color(0xFFFFBF00)),
                      minimumSize: const Size(50, actionHeight),
                      maximumSize: const Size(50, actionHeight),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(actionRadius),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Icon(Icons.videocam_rounded, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ],
    );
  }

  bool get _hasAnyActiveEditorSelection {
    if (_isGlobalSelection ||
        (_overlayKey.currentState?.hasSelection ?? false)) {
      return true;
    }
    for (final c in _controllers) {
      if (c.isGlobalSelected) return true;
      final external = c.externalSelection;
      if (external != null && external.isValid && !external.isCollapsed) {
        return true;
      }
      final native = c.selection;
      if (native.isValid && !native.isCollapsed) return true;
    }
    return false;
  }

  bool _isPointInsideSelectionPreservingChrome(Offset globalPosition) {
    return _isPointInsideKey(_appSelectionToolbarKey, globalPosition) ||
        _isPointInsideKey(_formattingToolbarKey, globalPosition);
  }

  bool _isPointInsideKey(GlobalKey key, Offset globalPosition) {
    final context = key.currentContext;
    if (context == null) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    return (topLeft & box.size).contains(globalPosition);
  }

  Widget _buildAppSelectionToolbar() {
    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onPressed,
    }) {
      return Tooltip(
        message: label,
        child: TextButton.icon(
          onPressed: () {
            ContextMenuController.removeAny();
            onPressed();
          },
          icon: Icon(icon, size: 18, color: const Color(0xFFFFBF00)),
          label: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    return Material(
      key: _appSelectionToolbarKey,
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xF21A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x99FFBF00)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            action(
              icon: Icons.content_cut_rounded,
              label: 'Cut',
              onPressed: _onCut,
            ),
            action(
              icon: Icons.content_copy_rounded,
              label: 'Copy',
              onPressed: _onCopyClean,
            ),
            action(
              icon: Icons.content_paste_rounded,
              label: 'Paste',
              onPressed: () => unawaited(_onPaste()),
            ),
            action(
              icon: Icons.select_all_rounded,
              label: 'All',
              onPressed: _selectAllBlocks,
            ),
            IconButton(
              tooltip: 'Clear selection',
              onPressed: () {
                ContextMenuController.removeAny();
                _clearGlobalSelection();
              },
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 30,
                height: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
