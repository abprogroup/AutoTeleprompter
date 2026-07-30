import 'package:flutter/services.dart';

import 'markup_decoration_service.dart';

/// Ported from Windows' `editor_inline_style_operation.dart` - only the two
/// color-inversion-specific methods (`applySelectionColorInvert`,
/// `applyWholeScriptHighlightColorInvert`). Android's general inline-style
/// toggle/parameterized-tag application already exists independently in
/// `styling_logic_mixin.dart` (`wrapSelection`/`applyInlineProperty`, built
/// directly against `MarkupController` rather than pure `TextEditingValue`
/// in/out) - color inversion is genuinely new capability, not an
/// architecture Android was missing, so it gets its own small file instead
/// of duplicating the general toggle engine.
///
/// Available capability, not yet wired into the editor's "Invert Colors"
/// toolbar button (`android_parity_gaps.md` #5) - that requires threading
/// through `script_editor_screen.dart`'s selection/history/global-selection
/// state exactly right, which deserves its own careful pass rather than a
/// blind copy of Windows' `handleInvertColors` (which references several
/// Windows-editor-specific internals: `_overlayKey`, `externalSelection`,
/// `_styleTargets()`). The presenter/remote whole-script invert (no text
/// selection involved) IS wired - see `teleprompter_screen.session_stt.dart`
/// `_togglePresenterColorInversion` and `ScriptColorInversionService`.
class EditorColorInversionOperation {
  const EditorColorInversionOperation._();

  static TextEditingValue applySelectionColorInvert({
    required String text,
    required TextSelection selection,
    required String defaultTextColor,
    required String scriptBackgroundColor,
  }) {
    final sel = _safeSelection(text, selection);
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
        // by moving the text color to the (old) script background color.
        // Without this, imported text keeps its baked-in color (e.g. white)
        // and goes invisible once the script background swaps to that color.
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

  static TextSelection _safeSelection(String text, TextSelection selection) {
    final start = selection.start.clamp(0, text.length).toInt();
    final end = selection.end.clamp(start, text.length).toInt();
    return TextSelection(baseOffset: start, extentOffset: end);
  }

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
