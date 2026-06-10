part of 'script_editor_screen.dart';

extension _ScriptEditorVerticalLayoutBuilderParts on _ScriptEditorScreenState {
  _VerticalLayoutInfo _getVerticalLayout(
    int index, {
    TextSelection? selection,
  }) {
    final controller = _controllers[index];
    final settings = ref.read(settingsProvider);
    final isRtl = _editorBlockResolvedRtl(index);
    final textAlign = EditorTextGeometryService.resolveTextAlign(
      controller.text,
      isRtl: isRtl,
    );

    final style = TextStyle(
      color: Colors.white,
      fontSize: settings.fontSize,
      height: settings.lineSpacing,
      letterSpacing: settings.letterSpacing,
      wordSpacing: settings.wordSpacing,
    );
    final maxFontSize = EditorTextGeometryService.maxFontSize(
      controller.text,
      settings.fontSize,
    );
    final strutStyle = StrutStyle(
      fontSize: maxFontSize,
      height: settings.lineSpacing,
      forceStrutHeight: true,
    );

    double width = 800;
    final context = _blockKeys[index].currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        width = box.size.width - 30;
      }
    }

    final span = controller.text.isEmpty
        ? TextSpan(text: ' ', style: style)
        : controller.buildTextSpan(
            context: context ?? this.context,
            style: style,
            withComposing: false,
          );
    final painter = TextPainter(
      text: span,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: textAlign,
      strutStyle: strutStyle,
    );
    final double layoutWidth = width > 0 ? width : 800.0;
    painter.layout(maxWidth: layoutWidth);

    return _VerticalLayoutInfo(
      painter,
      selection ?? controller.selection,
      isRtl: isRtl,
      layoutWidth: layoutWidth,
    );
  }
}
