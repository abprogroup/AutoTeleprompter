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
  final VoidCallback onPaste;
  final VoidCallback onExtendSelection;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSearch;
  final bool hasBookmark;
  final VoidCallback onBookmarkTap;

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
    required this.onPaste,
    required this.onExtendSelection,
    required this.onUndo,
    required this.onRedo,
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
      color: Color(settings.futureWordColor),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasBookmark)
            Positioned(
              left: 0,
              top: 2,
              child: Tooltip(
                message: 'Tap to remove bookmark',
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onBookmarkTap,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.bookmark,
                      color: Color(0xFFFFBF00),
                      size: 18,
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
                SingleActivator(LogicalKeyboardKey.keyX, control: true):
                    _CutIntent(),
                SingleActivator(LogicalKeyboardKey.keyX, meta: true):
                    _CutIntent(),
                SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    _PasteIntent(),
                SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                    _PasteIntent(),
                // Undo/Redo: intercept BEFORE EditableText's internal handler
                // so Ctrl+Z routes to the global history stack, not the per-
                // controller undo stack that only knows about the current block.
                SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                    _UndoIntent(),
                SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                    _UndoIntent(),
                SingleActivator(LogicalKeyboardKey.keyY, control: true):
                    _RedoIntent(),
                SingleActivator(LogicalKeyboardKey.keyY, meta: true):
                    _RedoIntent(),
                SingleActivator(LogicalKeyboardKey.keyZ,
                    control: true, shift: true): _RedoIntent(),
                SingleActivator(LogicalKeyboardKey.keyZ,
                    meta: true, shift: true): _RedoIntent(),
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
                  _CutIntent: CallbackAction<_CutIntent>(onInvoke: (_) {
                    onCut();
                    return null;
                  }),
                  _PasteIntent: CallbackAction<_PasteIntent>(onInvoke: (_) {
                    onPaste();
                    return null;
                  }),
                  _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
                    onUndo();
                    return null;
                  }),
                  _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
                    onRedo();
                    return null;
                  }),
                  _SearchIntent: CallbackAction<_SearchIntent>(onInvoke: (_) {
                    onSearch();
                    return null;
                  }),
                  // Override internal EditableText intents so Cmd/Ctrl+C/X/V/A
                  // route through our markup-aware handlers. CopySelectionTextIntent
                  // covers BOTH copy and cut: cut is built via the `.cut(...)`
                  // factory which sets collapseSelection=true. Branch on that
                  // so context-menu "Cut" actually deletes the selection.
                  CopySelectionTextIntent:
                      CallbackAction<CopySelectionTextIntent>(
                    onInvoke: (intent) {
                      if (intent.collapseSelection) {
                        onCut();
                      } else {
                        onCopy();
                      }
                      return null;
                    },
                  ),
                  PasteTextIntent: CallbackAction<PasteTextIntent>(
                    onInvoke: (_) {
                      onPaste();
                      return null;
                    },
                  ),
                  SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                    onInvoke: (_) {
                      onSelectAll();
                      return null;
                    },
                  ),
                  UndoTextIntent: CallbackAction<UndoTextIntent>(
                    onInvoke: (_) {
                      onUndo();
                      return null;
                    },
                  ),
                  RedoTextIntent: CallbackAction<RedoTextIntent>(
                    onInvoke: (_) {
                      onRedo();
                      return null;
                    },
                  ),
                },
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      selectionColor: Colors.transparent,
                    ),
                  ),
                  child: _EditorRenderEditableDecorations(
                    controller: controller,
                    selection: paintSelection,
                    textDirection: textDirection,
                    child: TextField(
                      // Android native handles/toolbars may seed a cursor/range,
                      // but all script Cut/Copy/Paste/Select All commands belong
                      // to the app-owned toolbar. Keep ghost controls installed
                      // from first touch so native UI cannot appear for one frame
                      // before overlay promotion catches up.
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

                        if (hasPartialNativeSelection &&
                            !isGlobalSelected &&
                            !hasOverlaySelection &&
                            !hasExternalRange) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onExtendSelection();
                            ContextMenuController.removeAny();
                          });
                        }

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
