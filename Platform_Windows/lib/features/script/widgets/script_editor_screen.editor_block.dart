part of 'script_editor_screen.dart';

class _EditorBlock extends StatelessWidget {
  final MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final VoidCallback onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onSearch;
  final bool hasBookmark;
  final VoidCallback onBookmarkTap;

  const _EditorBlock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.settings,
    required this.isGlobalSelected,
    required this.onSubmitted,
    required this.onTap,
    required this.onSelectAll,
    required this.onCopy,
    required this.onSearch,
    required this.hasBookmark,
    required this.onBookmarkTap,
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasBookmark)
            Positioned(
              left: 0,
              top: 2,
              child: Tooltip(
                message: 'Delete bookmark',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onBookmarkTap,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text(
                      '»',
                      style: TextStyle(
                        color: Color(0xFFFFBF00),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 30),
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
                SingleActivator(LogicalKeyboardKey.keyF,
                    control: true, shift: true): _SearchIntent(),
                SingleActivator(LogicalKeyboardKey.keyF,
                    meta: true, shift: true): _SearchIntent(),
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
                  _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) {
                    onSearch();
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
                },
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      // Always transparent: all amber selection rendering is handled
                      // by MarkupController.buildTextSpan via externalSelection /
                      // isGlobalSelected. Native RenderEditable must never paint its
                      // own amber highlight or it leaks through when _isGlobalSelection
                      // flips to false during a handle drag (Bug 2 fix v4.0.6).
                      selectionColor: Colors.transparent,
                    ),
                  ),
                  child: TextField(
                    selectionControls: GhostSelectionControls(),
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
                      final List<ContextMenuButtonItem> items =
                          editableTextState.contextMenuButtonItems;
                      final List<ContextMenuButtonItem> customItems = [];
                      bool hasSelectAll = false;
                      for (final item in items) {
                        if (item.type == ContextMenuButtonType.selectAll) {
                          hasSelectAll = true;
                          customItems.add(ContextMenuButtonItem(
                            onPressed: () {
                              ContextMenuController.removeAny();
                              onSelectAll();
                            },
                            type: ContextMenuButtonType.selectAll,
                          ));
                        } else if (item.type == ContextMenuButtonType.copy) {
                          customItems.add(ContextMenuButtonItem(
                            onPressed: () {
                              ContextMenuController.removeAny();
                              onCopy();
                            },
                            type: ContextMenuButtonType.copy,
                          ));
                        } else {
                          customItems.add(item);
                        }
                      }
                      // Force-inject a global Select All even when the native menu
                      // omits it (e.g. the block is already fully selected).
                      if (!hasSelectAll) {
                        customItems.add(ContextMenuButtonItem(
                          onPressed: () {
                            ContextMenuController.removeAny();
                            onSelectAll();
                          },
                          type: ContextMenuButtonType.selectAll,
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
