part of 'script_editor_screen.dart';

class _EditorBlock extends StatelessWidget {
  final MarkupController controller;
  final FocusNode focusNode;
  final AppSettings settings;
  final bool isGlobalSelected;
  final bool? inheritedRtl;
  final VoidCallback onSubmitted;
  final VoidCallback onTap;
  final VoidCallback onSelectAll;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onPaste;
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
    this.inheritedRtl,
    required this.onSubmitted,
    required this.onTap,
    required this.onSelectAll,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onUndo,
    required this.onRedo,
    required this.onSearch,
    required this.hasBookmark,
    required this.onBookmarkTap,
  });

  TextAlign? _markupAlign(String text) {
    if (RegExp(r'\[(?:align=)?center\]').hasMatch(text)) {
      return TextAlign.center;
    }
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

  @override
  Widget build(BuildContext context) {
    final isRtl = inheritedRtl ??
        EditorTextGeometryService.resolveTextRtl(controller.text);
    final markupAlign = _markupAlign(controller.text);
    final textAlign = markupAlign ?? (isRtl ? TextAlign.right : TextAlign.left);
    final textDirection = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final maxFontSize = EditorTextGeometryService.maxFontSize(
        controller.text, settings.fontSize);
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
                    textSelectionTheme: const TextSelectionThemeData(
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
                          } else if (item.type == ContextMenuButtonType.cut) {
                            customItems.add(ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onCut();
                              },
                              type: ContextMenuButtonType.cut,
                            ));
                          } else if (item.type == ContextMenuButtonType.paste) {
                            customItems.add(ContextMenuButtonItem(
                              onPressed: () {
                                ContextMenuController.removeAny();
                                onPaste();
                              },
                              type: ContextMenuButtonType.paste,
                            ));
                          } else {
                            customItems.add(item);
                          }
                        }
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
          ),
        ],
      ),
    );
  }
}

class _EditorRenderEditableDecorations extends SingleChildRenderObjectWidget {
  final TextEditingController controller;
  final TextSelection? selection;
  final TextDirection textDirection;

  const _EditorRenderEditableDecorations({
    required this.controller,
    required this.selection,
    required this.textDirection,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEditorRenderEditableDecorations(
      controller: controller,
      selection: selection,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderEditorRenderEditableDecorations renderObject,
  ) {
    renderObject
      ..controller = controller
      ..selection = selection
      ..textDirection = textDirection;
  }
}

class _RenderEditorRenderEditableDecorations extends RenderProxyBox {
  TextEditingController _controller;
  TextSelection? _selection;
  TextDirection _textDirection;
  bool _listeningToController = false;

  _RenderEditorRenderEditableDecorations({
    required TextEditingController controller,
    required TextSelection? selection,
    required TextDirection textDirection,
  })  : _controller = controller,
        _selection = selection,
        _textDirection = textDirection;

  String get _rawText => _controller.text;

  set controller(TextEditingController value) {
    if (identical(value, _controller)) return;
    _stopControllerListener();
    _controller = value;
    _startControllerListener();
    markNeedsPaint();
  }

  set selection(TextSelection? value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _startControllerListener();
  }

  @override
  void detach() {
    _stopControllerListener();
    super.detach();
  }

  void _startControllerListener() {
    if (_listeningToController) return;
    _controller.addListener(_handleControllerChanged);
    _listeningToController = true;
  }

  void _stopControllerListener() {
    if (!_listeningToController) return;
    _controller.removeListener(_handleControllerChanged);
    _listeningToController = false;
  }

  void _handleControllerChanged() {
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final editable = _findRenderEditable(child);
    if (editable == null) {
      super.paint(context, offset);
      return;
    }

    final editableOffset = editable.localToGlobal(Offset.zero, ancestor: this);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(
        offset.dx + editableOffset.dx, offset.dy + editableOffset.dy);
    _paintStyleBackgrounds(canvas, editable);
    _paintActiveSelection(canvas, editable);
    canvas.restore();

    super.paint(context, offset);

    canvas.save();
    canvas.translate(
        offset.dx + editableOffset.dx, offset.dy + editableOffset.dy);
    _paintUnderlines(canvas, editable);
    canvas.restore();
  }

  RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  void _paintStyleBackgrounds(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomDocxDecorationPainting || _rawText.isEmpty) return;
    for (final range in MarkupDecorationParser.decorationRanges(_rawText)) {
      if (range.type != MarkupDecorationType.background) continue;
      final paintable = MarkupDecorationParser.paintableContentRange(
        _rawText,
        range,
      );
      if (paintable == null) continue;
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(
          baseOffset: paintable.start,
          extentOffset: paintable.end,
        ),
        gapTolerance: MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
      );
      _paintBands(
        canvas,
        editable,
        bands,
        range.color ?? Colors.transparent,
        applyBackgroundTail: true,
      );
    }
  }

  void _paintActiveSelection(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomEditorSelectionPainting) return;
    final activeSelection = _selection;
    if (activeSelection == null ||
        !activeSelection.isValid ||
        activeSelection.isCollapsed) {
      return;
    }
    final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
      editable,
      activeSelection,
      gapTolerance: MarkupDecorationBoxMerger.styleBackgroundGapTolerance,
    );
    _paintBands(
      canvas,
      editable,
      bands,
      const Color(0x66FFBF00),
      applyBackgroundTail: false,
    );
  }

  void _paintUnderlines(Canvas canvas, RenderEditable editable) {
    if (!kUseCustomDocxDecorationPainting || _rawText.isEmpty) return;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;
    for (final range in MarkupDecorationParser.decorationRanges(_rawText)) {
      if (range.type != MarkupDecorationType.underline) continue;
      final paintable = MarkupDecorationParser.paintableContentRange(
        _rawText,
        range,
      );
      if (paintable == null) continue;
      final bands = MarkupRenderEditableGeometry.mergedBandsForSelection(
        editable,
        TextSelection(
          baseOffset: paintable.start,
          extentOffset: paintable.end,
        ),
        gapTolerance: MarkupDecorationBoxMerger.styleUnderlineGapTolerance,
      );
      for (final rect in bands) {
        final leftTail = _textDirection == TextDirection.rtl
            ? MarkupDecorationBoxMerger.styleUnderlineVisualEndTail
            : 0.0;
        final rightTail = _textDirection == TextDirection.rtl
            ? 0.0
            : MarkupDecorationBoxMerger.styleUnderlineVisualEndTail;
        final left = (rect.left - leftTail).clamp(0.0, editable.size.width);
        final right = (rect.right + rightTail).clamp(0.0, editable.size.width);
        if (right <= left) continue;
        final y = rect.bottom - paint.strokeWidth * 0.5;
        canvas.drawLine(Offset(left, y), Offset(right, y), paint);
      }
    }
  }

  void _paintBands(
    Canvas canvas,
    RenderEditable editable,
    List<Rect> bands,
    Color color, {
    required bool applyBackgroundTail,
  }) {
    if (color.a <= 0 || bands.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final rect in bands) {
      final leftTail = !applyBackgroundTail
          ? 0.0
          : _textDirection == TextDirection.rtl
              ? MarkupDecorationBoxMerger.styleBackgroundVisualEndTail
              : MarkupDecorationBoxMerger.styleBackgroundInnerTail;
      final rightTail = !applyBackgroundTail
          ? 0.0
          : _textDirection == TextDirection.rtl
              ? MarkupDecorationBoxMerger.styleBackgroundInnerTail
              : MarkupDecorationBoxMerger.styleBackgroundVisualEndTail;
      final band = Rect.fromLTRB(
        (rect.left - leftTail).clamp(0.0, editable.size.width).toDouble(),
        rect.top,
        (rect.right + rightTail).clamp(0.0, editable.size.width).toDouble(),
        rect.bottom,
      );
      if (band.width <= 0 || band.height <= 0) continue;
      final radius = Radius.circular((band.height * 0.10).clamp(2.0, 6.0));
      canvas.drawRRect(RRect.fromRectAndRadius(band, radius), paint);
    }
  }
}
