import 'package:flutter/services.dart';

import 'markup_decoration_service.dart';

class EditorInlineStyleOperation {
  const EditorInlineStyleOperation._();

  static TextSelection safeSelection(
    String text,
    TextSelection selection,
  ) {
    final start = selection.start.clamp(0, text.length).toInt();
    final end = selection.end.clamp(start, text.length).toInt();
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  static SelectionStyleState selectionState(
    String text,
    TextSelection selection, {
    required String open,
    required String close,
  }) {
    final sel = safeSelection(text, selection);
    if (sel.isCollapsed) {
      return SelectionStyleState(0, isActiveAt(text, sel.start, open, close));
    }

    var active = false;
    var visibleCount = 0;
    var styledCount = 0;
    var cursor = 0;

    void visitContent(int start, int end) {
      if (end <= start) return;
      final from = start < sel.start ? sel.start : start;
      final to = end > sel.end ? sel.end : end;
      if (to <= from) return;
      final count = to - from;
      visibleCount += count;
      if (active) styledCount += count;
    }

    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      visitContent(cursor, match.start);
      final tag = match.group(0)!;
      if (_isToggleTag(tag, open, close)) {
        active = !active;
      } else if (_isTargetOpen(tag, open, close)) {
        active = true;
      } else if (_isTargetClose(tag, open, close)) {
        active = false;
      }
      cursor = match.end;
    }
    visitContent(cursor, text.length);

    return SelectionStyleState(
      visibleCount,
      visibleCount > 0 && styledCount == visibleCount,
    );
  }

  static bool isActiveAt(
    String text,
    int rawOffset,
    String open,
    String close,
  ) {
    final offset = rawOffset.clamp(0, text.length).toInt();
    var active = false;
    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      if (match.start >= offset) break;
      final tag = match.group(0)!;
      if (_isToggleTag(tag, open, close)) {
        active = !active;
      } else if (_isTargetOpen(tag, open, close)) {
        active = true;
      } else if (_isTargetClose(tag, open, close)) {
        active = false;
      }
    }
    return active;
  }

  static TextEditingValue applyForced({
    required String text,
    required TextSelection selection,
    required String open,
    required String close,
    required bool enable,
  }) {
    final sel = safeSelection(text, selection);
    if (sel.isCollapsed) {
      final visual = MarkupDecorationParser.rawToVisibleOffset(text, sel.start);
      final safeRaw = MarkupDecorationParser.visibleToRawOffset(text, visual);
      final next =
          text.substring(0, safeRaw) + open + close + text.substring(safeRaw);
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: safeRaw + open.length),
      );
    }

    final buffer = StringBuffer();
    var sourceActive = false;
    var outputActive = false;
    var cursor = 0;
    int? newSelectionStart;
    var newSelectionEnd = 0;

    void setOutputActive(bool value) {
      if (outputActive == value) return;
      buffer.write(value ? open : close);
      outputActive = value;
    }

    void emitContent(int start, int end) {
      if (end <= start) return;
      for (var i = start; i < end; i++) {
        final selected = i >= sel.start && i < sel.end;
        final desired = selected ? enable : sourceActive;
        setOutputActive(desired);
        if (selected && newSelectionStart == null) {
          newSelectionStart = buffer.length;
        }
        buffer.write(text[i]);
        if (selected) newSelectionEnd = buffer.length;
      }
    }

    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      emitContent(cursor, match.start);
      final tag = match.group(0)!;
      if (_isToggleTag(tag, open, close)) {
        sourceActive = !sourceActive;
      } else if (_isTargetOpen(tag, open, close)) {
        sourceActive = true;
      } else if (_isTargetClose(tag, open, close)) {
        sourceActive = false;
      } else {
        buffer.write(tag);
      }
      cursor = match.end;
    }
    emitContent(cursor, text.length);
    setOutputActive(false);

    final selectionStart = newSelectionStart ?? buffer.length;
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset:
            newSelectionEnd < selectionStart ? selectionStart : newSelectionEnd,
      ),
    );
  }

  static TextEditingValue applyParameterized({
    required String text,
    required TextSelection selection,
    required String family,
    required String value,
  }) {
    final sel = safeSelection(text, selection);
    final open = '[$family=$value]';
    final close = '[/$family]';
    if (sel.isCollapsed) {
      final visual = MarkupDecorationParser.rawToVisibleOffset(text, sel.start);
      final safeRaw = MarkupDecorationParser.visibleToRawOffset(text, visual);
      final next =
          text.substring(0, safeRaw) + open + close + text.substring(safeRaw);
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: safeRaw + open.length),
      );
    }

    final buffer = StringBuffer();
    String? sourceValue;
    String? outputValue;
    var cursor = 0;
    int? newSelectionStart;
    var newSelectionEnd = 0;

    void setOutputValue(String? next) {
      if (outputValue == next) return;
      if (outputValue != null) buffer.write(close);
      if (next != null) buffer.write('[$family=$next]');
      outputValue = next;
    }

    void emitContent(int start, int end) {
      if (end <= start) return;
      for (var i = start; i < end; i++) {
        final selected = i >= sel.start && i < sel.end;
        setOutputValue(selected ? value : sourceValue);
        if (selected && newSelectionStart == null) {
          newSelectionStart = buffer.length;
        }
        buffer.write(text[i]);
        if (selected) newSelectionEnd = buffer.length;
      }
    }

    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      emitContent(cursor, match.start);
      final tag = match.group(0)!;
      final targetOpenValue = _targetParameterizedOpenValue(tag, family);
      if (targetOpenValue != null) {
        sourceValue = targetOpenValue;
      } else if (tag == close) {
        sourceValue = null;
      } else {
        setOutputValue(null);
        buffer.write(tag);
      }
      cursor = match.end;
    }
    emitContent(cursor, text.length);
    setOutputValue(null);

    final selectionStart = newSelectionStart ?? buffer.length;
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset:
            newSelectionEnd < selectionStart ? selectionStart : newSelectionEnd,
      ),
    );
  }

  static TextEditingValue applySelectionColorInvert({
    required String text,
    required TextSelection selection,
    required String defaultTextColor,
    required String scriptBackgroundColor,
  }) {
    final sel = safeSelection(text, selection);
    if (sel.isCollapsed) {
      return TextEditingValue(
        text: text,
        selection: selection,
      );
    }

    final defaultText = _normalizeHex(defaultTextColor);
    final scriptBackground = _normalizeHex(scriptBackgroundColor);
    final buffer = StringBuffer();
    String? sourceTextColor;
    String? sourceBackgroundColor;
    String? outputTextColor;
    String? outputBackgroundColor;
    var cursor = 0;
    var changed = false;
    int? newSelectionStart;
    var newSelectionEnd = 0;

    void setOutput({
      required String? textColor,
      required String? backgroundColor,
    }) {
      if (outputBackgroundColor != backgroundColor) {
        if (outputBackgroundColor != null) buffer.write('[/bg]');
        outputBackgroundColor = null;
      }
      if (outputTextColor != textColor) {
        if (outputBackgroundColor != null) {
          buffer.write('[/bg]');
          outputBackgroundColor = null;
        }
        if (outputTextColor != null) buffer.write('[/color]');
        if (textColor != null) buffer.write('[color=#$textColor]');
        outputTextColor = textColor;
      }
      if (outputBackgroundColor != backgroundColor) {
        if (backgroundColor != null) buffer.write('[bg=#$backgroundColor]');
        outputBackgroundColor = backgroundColor;
      }
    }

    void emitContent(int start, int end) {
      if (end <= start) return;
      for (var i = start; i < end; i++) {
        final selected = i >= sel.start && i < sel.end;
        String? nextTextColor = sourceTextColor;
        String? nextBackgroundColor = sourceBackgroundColor;
        if (selected) {
          final oldText = sourceTextColor ?? defaultText;
          final oldBackground = sourceBackgroundColor;
          nextTextColor = oldBackground ?? scriptBackground;
          nextBackgroundColor = oldText;
          changed = true;
          newSelectionStart ??= buffer.length;
        }
        setOutput(
          textColor: nextTextColor,
          backgroundColor: nextBackgroundColor,
        );
        buffer.write(text[i]);
        if (selected) newSelectionEnd = buffer.length;
      }
    }

    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      emitContent(cursor, match.start);
      final tag = match.group(0)!;
      final color = _targetParameterizedOpenValue(tag, 'color');
      final background = _targetParameterizedOpenValue(tag, 'bg');
      if (color != null) {
        sourceTextColor = _normalizeHex(color);
      } else if (tag == '[/color]') {
        sourceTextColor = null;
      } else if (background != null) {
        sourceBackgroundColor = _normalizeHex(background);
      } else if (tag == '[/bg]') {
        sourceBackgroundColor = null;
      } else {
        buffer.write(tag);
      }
      cursor = match.end;
    }
    emitContent(cursor, text.length);
    setOutput(textColor: null, backgroundColor: null);

    if (!changed) {
      return TextEditingValue(text: text, selection: selection);
    }
    final selectionStart = newSelectionStart ?? buffer.length;
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection(
        baseOffset: selectionStart,
        extentOffset:
            newSelectionEnd < selectionStart ? selectionStart : newSelectionEnd,
      ),
    );
  }

  static TextEditingValue applyWholeScriptHighlightColorInvert({
    required String text,
    required String defaultTextColor,
    required String scriptBackgroundColor,
  }) {
    final defaultText = _normalizeHex(defaultTextColor);
    final scriptBg = _normalizeHex(scriptBackgroundColor);
    final buffer = StringBuffer();
    String? sourceTextColor;
    String? sourceBackgroundColor;
    String? outputTextColor;
    String? outputBackgroundColor;
    var cursor = 0;
    var changed = false;

    void setOutput({
      required String? textColor,
      required String? backgroundColor,
    }) {
      if (outputBackgroundColor != backgroundColor) {
        if (outputBackgroundColor != null) buffer.write('[/bg]');
        outputBackgroundColor = null;
      }
      if (outputTextColor != textColor) {
        if (outputBackgroundColor != null) {
          buffer.write('[/bg]');
          outputBackgroundColor = null;
        }
        if (outputTextColor != null) buffer.write('[/color]');
        if (textColor != null) buffer.write('[color=#$textColor]');
        outputTextColor = textColor;
      }
      if (outputBackgroundColor != backgroundColor) {
        if (backgroundColor != null) buffer.write('[bg=#$backgroundColor]');
        outputBackgroundColor = backgroundColor;
      }
    }

    void emitContent(int start, int end) {
      if (end <= start) return;
      final oldBackground = sourceBackgroundColor;
      String? nextTextColor;
      String? nextBackgroundColor;
      if (oldBackground != null) {
        // Highlighted run: swap text color <-> highlight color.
        nextTextColor = oldBackground;
        nextBackgroundColor = sourceTextColor ?? defaultText;
        changed = true;
      } else if (sourceTextColor != null) {
        // Explicitly-colored text with no highlight: invert text <-> background
        // by moving the text color to the (old) script background color. Without
        // this, RTF-imported text keeps its baked-in color (e.g. white) and goes
        // invisible once the script background swaps to that same color.
        nextTextColor = scriptBg;
        nextBackgroundColor = null;
        changed = true;
      } else {
        // Truly plain text carries no color tag; it follows the swapped
        // futureWordColor setting, so leave it untagged.
        nextTextColor = null;
        nextBackgroundColor = null;
      }
      setOutput(
        textColor: nextTextColor,
        backgroundColor: nextBackgroundColor,
      );
      buffer.write(text.substring(start, end));
    }

    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      emitContent(cursor, match.start);
      final tag = match.group(0)!;
      final color = _targetParameterizedOpenValue(tag, 'color');
      final background = _targetParameterizedOpenValue(tag, 'bg');
      if (color != null) {
        sourceTextColor = _normalizeHex(color);
      } else if (tag == '[/color]') {
        sourceTextColor = null;
      } else if (background != null) {
        sourceBackgroundColor = _normalizeHex(background);
      } else if (tag == '[/bg]') {
        sourceBackgroundColor = null;
      } else {
        buffer.write(tag);
      }
      cursor = match.end;
    }
    emitContent(cursor, text.length);
    setOutput(textColor: null, backgroundColor: null);

    if (!changed) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }

  static bool _isTargetOpen(String tag, String open, String close) {
    if (_isToggleTag(tag, open, close)) return false;
    return tag == open;
  }

  static bool _isTargetClose(String tag, String open, String close) {
    if (_isToggleTag(tag, open, close)) return false;
    return tag == close;
  }

  static bool _isToggleTag(String tag, String open, String close) =>
      open == close && tag == open;

  static String? _targetParameterizedOpenValue(String tag, String family) {
    final prefix = '[$family=';
    if (!tag.startsWith(prefix) || !tag.endsWith(']')) return null;
    return tag.substring(prefix.length, tag.length - 1);
  }

  static String _normalizeHex(String value) {
    final cleaned = value
        .trim()
        .replaceFirst('#', '')
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (cleaned.length >= 6) {
      return cleaned.substring(cleaned.length - 6).toUpperCase();
    }
    return cleaned.padLeft(6, '0').toUpperCase();
  }
}

class SelectionStyleState {
  final int visibleCount;
  final bool fullyStyled;

  const SelectionStyleState(this.visibleCount, this.fullyStyled);
}
