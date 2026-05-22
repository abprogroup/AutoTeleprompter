part of 'script_editor_screen.dart';

class _EditorBlock extends StatelessWidget {
  final MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final bool hasOverlaySelection;
  final bool? inheritedRtl;
  final VoidCallback onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExtendSelection;
  final VoidCallback? onPaste;
  final bool hasBookmark;
  final VoidCallback onBookmarkTap;
  final List<_EditorBookmarkAnchor> bookmarkAnchors;
  final ValueChanged<String> onInlineBookmarkTap;

  const _EditorBlock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.settings,
    required this.isGlobalSelected,
    required this.hasOverlaySelection,
    this.inheritedRtl,
    required this.onSubmitted,
    required this.onTap,
    required this.onSelectAll,
    required this.onCopy,
    required this.onCut,
    required this.onExtendSelection,
    required this.hasBookmark,
    required this.onBookmarkTap,
    required this.bookmarkAnchors,
    required this.onInlineBookmarkTap,
    this.onPaste,
  });

  TextAlign? _markupAlign(String text) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(text))
      return TextAlign.center;
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(text)) return TextAlign.right;
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(text)) return TextAlign.left;
    return null;
  }

  TextSelection? _selectionForCustomPaint() {
    final length = controller.text.length;
    if (length <= 0) return null;

    TextSelection? selection;
    if (isGlobalSelected || controller.isGlobalSelected) {
      selection = TextSelection(baseOffset: 0, extentOffset: length);
    } else if (controller.externalSelection != null) {
      final external = controller.externalSelection!;
      if (!external.isValid || external.isCollapsed) return null;
      selection = external;
    } else {
      final native = controller.selection;
      if (!native.isValid || native.isCollapsed) return null;
      selection = native;
    }

    final start = selection.start.clamp(0, length).toInt();
    final end = selection.end.clamp(start, length).toInt();
    if (end <= start) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  double _getMaxFontSize(String text, double defaultSize) {
    if (text.isEmpty) return defaultSize;
    final matches = RegExp(r'\[size=(\d+)\]').allMatches(text);
    if (matches.isEmpty) return defaultSize;
    double maxMatch = defaultSize;
    for (final m in matches) {
      final size = double.tryParse(m.group(1)!) ?? defaultSize;
      if (size > maxMatch) maxMatch = size;
    }
    return maxMatch;
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = inheritedRtl ??
        EditorTextGeometryService.resolveTextRtl(controller.text);
    final markupAlign = _markupAlign(controller.text);
    final textAlign = markupAlign ?? (isRtl ? TextAlign.right : TextAlign.left);
    final maxFontSize = _getMaxFontSize(controller.text, settings.fontSize);
    final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final editorTextStyle = TextStyle(
      color: Colors.white,
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );
    final editorStrutStyle = StrutStyle(
      fontSize: maxFontSize,
      height: settings.lineSpacing,
      forceStrutHeight: true,
    );
    const editorContentPadding = EdgeInsets.symmetric(vertical: 2);
    final paintSelection = _selectionForCustomPaint();
    final externalSelection = controller.externalSelection;
    final hasExternalRange = controller.isGlobalSelected ||
        (externalSelection != null &&
            externalSelection.isValid &&
            !externalSelection.isCollapsed);
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.ltr,
        children: [
          Expanded(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.keyA, control: true):
                    _SelectAllIntent(),
                SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                    _SelectAllIntent(),
                SingleActivator(LogicalKeyboardKey.keyC, control: true):
                    _CopyIntent(),
                SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                    _CopyIntent(),
              },
              child: Actions(
                actions: {
                  _SelectAllIntent:
                      CallbackAction<_SelectAllIntent>(onInvoke: (_) {
                    onSelectAll();
                    return null;
                  }),
                  _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (_) {
                    onCopy();
                    return null;
                  }),
                  // Override the internal EditableText intents too. These are
                  // marked Action.overridable inside EditableText, so placing
                  // our own handlers at this ancestor wins — catching both the
                  // keyboard Cmd+C and Flutter's internal copy dispatch paths.
                  CopySelectionTextIntent:
                      CallbackAction<CopySelectionTextIntent>(
                    onInvoke: (_) {
                      onCopy();
                      return null;
                    },
                  ),
                  SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                    onInvoke: (_) {
                      onSelectAll();
                      return null;
                    },
                  ),
                  if (onPaste != null)
                    PasteTextIntent: CallbackAction<PasteTextIntent>(
                      onInvoke: (_) {
                        onPaste!();
                        return null;
                      },
                    ),
                },
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: const TextSelectionThemeData(
                      // Transparent selection keeps markup-aware amber painting
                      // inside MarkupController. Native single-block handles may
                      // still appear when no global/overlay selection is active.
                      selectionColor: Colors.transparent,
                    ),
                  ),
                  child: _EditorRenderEditableDecorations(
                    controller: controller,
                    selection: paintSelection,
                    textDirection: textDirection,
                    child: TextField(
                      selectionControls: GhostSelectionControls(),
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: null,
                      onSubmitted: (_) => onSubmitted(),
                      onTap: onTap,
                      textDirection: textDirection,
                      textAlign: textAlign,
                      cursorColor: Colors.amber,
                      cursorHeight: maxFontSize,
                      strutStyle: editorStrutStyle,
                      style: editorTextStyle,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: editorContentPadding,
                      ),
                      contextMenuBuilder: (_, editableTextState) {
                        editableTextState.hideToolbar(false);
                        ContextMenuController.removeAny();
                        final selection = controller.selection;
                        final hasPartialNativeSelection = selection.isValid &&
                            !selection.isCollapsed &&
                            !(selection.start == 0 &&
                                selection.end == controller.text.length);

                        void adoptPartialSelectionAfterMenuBuild() {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onExtendSelection();
                            ContextMenuController.removeAny();
                          });
                        }

                        // When the block is globally selected, bypass editableTextState
                        // entirely. iOS asynchronously resets the native selection back
                        // to the original double-tapped word after Select All, so
                        // any native selected-text menu would serve word-scoped
                        // Cut/Copy actions instead of our global ones. The visible
                        // command surface is the app-owned selection toolbar in the
                        // parent Stack; native selected-text menus are suppressed
                        // while app selection is active.
                        if (isGlobalSelected ||
                            hasOverlaySelection ||
                            hasExternalRange) {
                          ContextMenuController.removeAny();
                          return const SizedBox.shrink();
                        }

                        // Native iOS selection detects the user's one-block
                        // intent, then the app overlay becomes the handle owner.
                        // The parent guards this handoff during Select All so a
                        // late word-selection event cannot downgrade full-script
                        // selection back to the originally double-tapped word.
                        if (hasPartialNativeSelection) {
                          adoptPartialSelectionAfterMenuBuild();
                        }

                        // The script editor owns Cut/Copy/Paste/Select All through
                        // _buildAppSelectionToolbar. UIKit may seed focus or a
                        // one-block range, but its native toolbar is never shown.
                        ContextMenuController.removeAny();
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
