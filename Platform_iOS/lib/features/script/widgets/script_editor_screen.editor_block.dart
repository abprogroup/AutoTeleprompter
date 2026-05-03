part of 'script_editor_screen.dart';

class _EditorBlock extends StatelessWidget {
  final MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final bool hasOverlaySelection;
  final VoidCallback onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onExtendSelection;
  final VoidCallback? onPaste;
  final bool hasBookmark;
  final VoidCallback onBookmarkTap;

  const _EditorBlock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.settings,
    required this.isGlobalSelected,
    required this.hasOverlaySelection,
    required this.onSubmitted,
    required this.onTap,
    required this.onSelectAll,
    required this.onCopy,
    required this.onCut,
    required this.onExtendSelection,
    required this.hasBookmark,
    required this.onBookmarkTap,
    this.onPaste,
  });

  TextAlign? _markupAlign(String text) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(text))
      return TextAlign.center;
    if (RegExp(r'\[(?:align=)?right\]').hasMatch(text)) return TextAlign.right;
    if (RegExp(r'\[(?:align=)?left\]').hasMatch(text)) return TextAlign.left;
    return null;
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
    final isRtl = controller.text.isHebrew;
    final markupAlign = _markupAlign(controller.text);
    final textAlign = markupAlign ?? (isRtl ? TextAlign.right : TextAlign.left);
    final maxFontSize = _getMaxFontSize(controller.text, settings.fontSize);
    final useGhostSelectionControls = isGlobalSelected || hasOverlaySelection;

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: TextDirection.ltr,
        children: [
          SizedBox(
            width: 28,
            child: hasBookmark
                ? Tooltip(
                    message: 'Delete bookmark',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onBookmarkTap,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          '»',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFFBF00),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
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
                  child: TextField(
                    selectionControls: useGhostSelectionControls
                        ? GhostSelectionControls()
                        : null,
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: null,
                    onSubmitted: (_) => onSubmitted(),
                    onTap: onTap,
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    textAlign: textAlign,
                    cursorColor: Colors.amber,
                    cursorHeight: maxFontSize,
                    strutStyle: StrutStyle(
                      fontSize: maxFontSize,
                      height: settings.lineSpacing,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: settings.fontSize,
                      height: settings.lineSpacing,
                      letterSpacing: settings.letterSpacing,
                      wordSpacing: settings.wordSpacing,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 2),
                    ),
                    contextMenuBuilder: (context, editableTextState) {
                      final selection = controller.selection;
                      final hasPartialNativeSelection = selection.isValid &&
                          !selection.isCollapsed &&
                          !(selection.start == 0 &&
                              selection.end == controller.text.length);
                      void selectAllAndReopenToolbar() {
                        ContextMenuController.removeAny();
                        onSelectAll();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Future<void>.delayed(
                              const Duration(milliseconds: 120), () {
                            if (editableTextState.mounted) {
                              onSelectAll();
                            }
                          });
                          Future<void>.delayed(
                              const Duration(milliseconds: 180), () {
                            if (editableTextState.mounted) {
                              editableTextState.showToolbar();
                            }
                          });
                        });
                      }

                      void adoptPartialSelectionAfterMenuBuild() {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onExtendSelection();
                        });
                      }

                      // When the block is globally selected, bypass editableTextState
                      // entirely. iOS asynchronously resets the native selection back
                      // to the original double-tapped word after Select All, so
                      // iterating contextMenuButtonItems would serve word-scoped
                      // Cut/Copy actions instead of our global ones.
                      if (isGlobalSelected || hasOverlaySelection) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onExtendSelection();
                                onCut();
                              },
                              type: ContextMenuButtonType.cut,
                            ),
                            ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onExtendSelection();
                                onCopy();
                              },
                              type: ContextMenuButtonType.copy,
                            ),
                            ContextMenuButtonItem(
                              onPressed: selectAllAndReopenToolbar,
                              type: ContextMenuButtonType.custom,
                              label: 'Select All',
                            ),
                            if (onPaste != null)
                              ContextMenuButtonItem(
                                onPressed: () {
                                  ContextMenuController.removeAny();
                                  onPaste!();
                                },
                                type: ContextMenuButtonType.custom,
                                label: 'Paste',
                              ),
                          ],
                        );
                      }

                      // Native iOS selection detects the user's one-block
                      // intent, then the app overlay becomes the handle owner.
                      // The parent guards this handoff during Select All so a
                      // late word-selection event cannot downgrade full-script
                      // selection back to the originally double-tapped word.
                      if (hasPartialNativeSelection) {
                        adoptPartialSelectionAfterMenuBuild();
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: [
                            ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onExtendSelection();
                                onCut();
                              },
                              type: ContextMenuButtonType.cut,
                            ),
                            ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onExtendSelection();
                                onCopy();
                              },
                              type: ContextMenuButtonType.copy,
                            ),
                            ContextMenuButtonItem(
                              onPressed: selectAllAndReopenToolbar,
                              type: ContextMenuButtonType.custom,
                              label: 'Select All',
                            ),
                            if (onPaste != null)
                              ContextMenuButtonItem(
                                onPressed: () {
                                  ContextMenuController.removeAny();
                                  onPaste!();
                                },
                                type: ContextMenuButtonType.custom,
                                label: 'Paste',
                              ),
                          ],
                        );
                      }

                      final List<ContextMenuButtonItem> items =
                          editableTextState.contextMenuButtonItems;
                      final List<ContextMenuButtonItem> customItems = [];
                      bool hasSelectAll = false;
                      for (final item in items) {
                        if (item.type == ContextMenuButtonType.selectAll) {
                          hasSelectAll = true;
                          customItems.add(ContextMenuButtonItem(
                            onPressed: selectAllAndReopenToolbar,
                            type: ContextMenuButtonType.custom,
                            label: 'Select All',
                          ));
                        } else if (item.type == ContextMenuButtonType.cut) {
                          customItems.add(ContextMenuButtonItem(
                            onPressed: () {
                              ContextMenuController.removeAny();
                              onCut();
                            },
                            type: ContextMenuButtonType.cut,
                          ));
                        } else if (item.type == ContextMenuButtonType.copy) {
                          customItems.add(ContextMenuButtonItem(
                            onPressed: () {
                              ContextMenuController.removeAny();
                              onCopy();
                            },
                            type: ContextMenuButtonType.copy,
                          ));
                        } else if (item.type == ContextMenuButtonType.paste &&
                            onPaste != null) {
                          customItems.add(ContextMenuButtonItem(
                            onPressed: () {
                              ContextMenuController.removeAny();
                              onPaste!();
                            },
                            type: ContextMenuButtonType.custom,
                            label: 'Paste',
                          ));
                        } else {
                          customItems.add(item);
                        }
                      }
                      // Force-inject Select All even when the native menu omits it.
                      if (!hasSelectAll) {
                        customItems.add(ContextMenuButtonItem(
                          onPressed: selectAllAndReopenToolbar,
                          type: ContextMenuButtonType.custom,
                          label: 'Select All',
                        ));
                      }
                      // Force-inject Paste when _blockClipboard is set but menu omits it.
                      if (onPaste != null &&
                          !customItems.any((i) =>
                              i.label == 'Paste' ||
                              i.type == ContextMenuButtonType.paste)) {
                        customItems.add(ContextMenuButtonItem(
                          onPressed: () {
                            ContextMenuController.removeAny();
                            onPaste!();
                          },
                          type: ContextMenuButtonType.custom,
                          label: 'Paste',
                        ));
                      }
                      return AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: editableTextState.contextMenuAnchors,
                        buttonItems: customItems,
                      );
                    },
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
