part of 'script_editor_screen.dart';

extension _ScriptEditorCursorDetectionParts on _ScriptEditorScreenState {
  Color? _detectColorAtCursor({required bool textColor, int? offset}) {
    final controller = _activeController;
    if (controller == null) return null;
    final text = controller.text;
    final off = offset ?? controller.selection.start;
    final tag = textColor ? '[color=' : '[bg=';
    final closeTag = textColor ? '[/color]' : '[/bg]';
    final matches = RegExp(RegExp.escape(tag) + r'([^\]]+)\]').allMatches(text);
    Color? found;
    for (final m in matches) {
      if (m.start <= off) {
        final nextClose = text.indexOf(closeTag, m.end);
        if (nextClose == -1 || nextClose >= off) {
          final hex = m.group(1)!.trim().replaceFirst('#', '');
          found = Color(int.tryParse('FF$hex', radix: 16) ??
              (textColor ? 0xFFFFFFFF : 0x00000000));
        }
      }
    }
    return found ?? const Color(0x00000000);
  }

  String _detectAlignAtCursor({int? offset}) {
    final controller = _activeController;
    if (controller == null) return 'left';
    final text = controller.text;
    final rawOff = offset ?? controller.selection.baseOffset;
    final off = rawOff.clamp(0, text.isEmpty ? 0 : text.length);
    final alignMatches =
        RegExp(r'\[(?:align=)?(center|left|right)\]').allMatches(text);
    String found = 'left';
    for (final m in alignMatches) {
      if (m.start <= off) {
        final val = m.group(1)!;
        final isNewFormat = m.group(0)!.startsWith('[align=');
        final closeTag = isNewFormat ? '[/align=$val]' : '[/$val]';
        final nextClose = text.indexOf(closeTag, m.end);
        if (nextClose == -1 || nextClose >= off) found = val;
      }
    }
    return found;
  }

  String _detectDirectionAtCursor() {
    final controller = _activeController;
    if (controller == null) return 'ltr';
    final text = controller.text;
    final explicit = EditorTextGeometryService.explicitTextDirection(text);
    if (explicit != null) return explicit;
    final index = _controllers.indexOf(controller);
    final isRtl = index >= 0
        ? _editorBlockResolvedRtl(index)
        : EditorTextGeometryService.resolveTextRtl(text);
    return isRtl ? 'rtl' : 'ltr';
  }

  bool _detectStyleAtCursor(String open, String close) {
    final controller = _activeController;
    if (controller == null) return false;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final mid = (start + (end - start) / 2).floor().clamp(0, text.length);
    bool isPointActive(int off) =>
        _detectStyleAtPoint(text, selection, off, open, close);
    if (selection.isCollapsed) return isPointActive(selection.baseOffset);
    return isPointActive(start) || isPointActive(end) || isPointActive(mid);
  }

  int _detectIntAtCursor(String prefix, int defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    int valAtPoint(int off) =>
        _detectIntAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2)
        .floor()
        .clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  String _detectStringAtCursor(String prefix, String defaultValue) {
    final controller = _activeController;
    if (controller == null) return defaultValue;
    final text = controller.text;
    final selection = controller.selection;
    String valAtPoint(int off) =>
        _detectStringAtPoint(text, selection, off, prefix, defaultValue);
    if (selection.isCollapsed) return valAtPoint(selection.baseOffset);
    final mid = (selection.start + (selection.end - selection.start) / 2)
        .floor()
        .clamp(0, text.length);
    final vMid = valAtPoint(mid);
    if (vMid != defaultValue) return vMid;
    return valAtPoint(selection.start);
  }

  bool _detectStyleAtPoint(
    String text,
    TextSelection selection,
    int off,
    String open,
    String close,
  ) {
    if (off < 0 || off > text.length) return false;
    bool check(int p) {
      if (p < 0 || p > text.length) return false;
      if (open == '**' && close == '**') {
        final subText = text.substring(0, p);
        final count = RegExp(r'\*\*').allMatches(subText).length;
        return count % 2 != 0;
      }
      final tagIdx = text.lastIndexOf(open, p);
      if (tagIdx == -1) return false;
      final exitIdx = text.indexOf(close, tagIdx + open.length);
      return exitIdx != -1 && exitIdx >= p;
    }

    if (check(off)) return true;
    for (int delta = 1; delta <= open.length + 2; delta++) {
      if (off - delta >= 0 && check(off - delta)) return true;
      if (off + delta <= text.length && check(off + delta)) return true;
    }
    return false;
  }

  int _detectIntAtPoint(
    String text,
    TextSelection selection,
    int off,
    String prefix,
    int defaultValue,
  ) {
    final openTag = '[$prefix';
    int check(int p) {
      if (p < 0 || p > text.length) return defaultValue;
      final tagIdx = text.lastIndexOf(openTag, p);
      if (tagIdx == -1) return defaultValue;
      final closeBracket = text.indexOf(']', tagIdx);
      if (closeBracket == -1 || closeBracket > p) return defaultValue;
      final tagName = prefix.split('=').first;
      final closeTag = '[/$tagName]';
      final exitIdx = text.indexOf(closeTag, tagIdx);
      if (exitIdx != -1 && exitIdx < p) return defaultValue;
      if (exitIdx == -1) return defaultValue;
      return int.tryParse(
            text.substring(tagIdx + openTag.length, closeBracket),
          ) ??
          defaultValue;
    }

    final atBoundary = check(off);
    if (atBoundary != defaultValue) return atBoundary;
    for (int delta = 1; delta <= openTag.length + 2; delta++) {
      if (off - delta >= 0) {
        final v = check(off - delta);
        if (v != defaultValue) return v;
      }
      if (off + delta <= text.length) {
        final v = check(off + delta);
        if (v != defaultValue) return v;
      }
    }
    return defaultValue;
  }

  String _detectStringAtPoint(
    String text,
    TextSelection selection,
    int off,
    String prefix,
    String defaultValue,
  ) {
    final openTag = '[$prefix';
    String check(int p) {
      if (p < 0 || p > text.length) return defaultValue;
      final tagIdx = text.lastIndexOf(openTag, p);
      if (tagIdx == -1) return defaultValue;
      final closeBracket = text.indexOf(']', tagIdx);
      if (closeBracket == -1 || closeBracket > p) return defaultValue;
      final tagName = prefix.split('=').first;
      final closeTag = '[/$tagName]';
      final exitIdx = text.indexOf(closeTag, tagIdx);
      if (exitIdx != -1 && exitIdx < p) return defaultValue;
      if (exitIdx == -1) return defaultValue;
      return text.substring(tagIdx + openTag.length, closeBracket);
    }

    final atBoundary = check(off);
    if (atBoundary != defaultValue) return atBoundary;
    for (int delta = 1; delta <= openTag.length + 2; delta++) {
      if (off - delta >= 0) {
        final v = check(off - delta);
        if (v != defaultValue) return v;
      }
      if (off + delta <= text.length) {
        final v = check(off + delta);
        if (v != defaultValue) return v;
      }
    }
    return defaultValue;
  }
}
