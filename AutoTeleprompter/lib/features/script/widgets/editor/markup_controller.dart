import 'package:flutter/material.dart';

/// Premium Highlighting Controller with inline markup rendering.
/// Renders bold/italic/underline/color/bg/size/font styles while visually
/// hiding tag characters, and supports multi-block selection highlighting
/// via the global selection overlay.
///
/// Architecture: controller.text returns RAW markup (with tags).
/// Tags are rendered invisible via _tagStyle in buildTextSpan.
/// StylingLogicMixin reads/writes controller.text directly.
class MarkupController extends TextEditingController {
  MarkupController({super.text});

  /// The selection range mapped to this block from the global overlay.
  TextSelection? externalSelection;

  /// Whether the entire block is selected (e.g. during Select All).
  bool isGlobalSelected = false;

  /// Force a repaint after mutating [externalSelection] or [isGlobalSelected].
  /// These fields live outside [value], so listeners otherwise won't fire.
  void refresh() => notifyListeners();

  static const TextStyle _tagStyle = TextStyle(
    color: Colors.transparent,
    fontSize: 0.1,
    letterSpacing: 0,
    wordSpacing: 0,
    height: 0,
  );

  static const Color _selectionBg = Color(0x66FFBF00);

  static final RegExp _tagRegex = RegExp(
    r'\*\*'
    r'|\[\/?u\]'
    r'|\[\/?i\]'
    r'|\[color=([^\]]+)\]|\[\/color\]'
    r'|\[bg=([^\]]+)\]|\[\/bg\]'
    r'|\[size=(\d+(?:\.\d+)?)\]|\[\/size\]'
    r'|\[font=([^\]]+)\]|\[\/font\]'
    r'|\[align=(center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[(center|left|right)\]|\[\/(?:center|left|right)\]'
    r'|\[rtl\]|\[\/rtl\]|\[ltr\]|\[\/ltr\]',
  );

  /// Tag-Skipping Backspace Guardian.
  /// Backspace over a hidden tag boundary walks past the tag(s) and
  /// deletes the first visible character before them, instead of
  /// chewing through tag chars one keypress at a time.
  @override
  set value(TextEditingValue newValue) {
    if (newValue == value) return;

    final oldText = text;
    String newText = newValue.text;
    TextSelection newSelection = newValue.selection;

    if (newText != oldText) {
      int prefix = 0;
      final minLen = oldText.length < newText.length ? oldText.length : newText.length;
      while (prefix < minLen &&
          oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
        prefix++;
      }
      int suffix = 0;
      while (suffix < (minLen - prefix) &&
          oldText.codeUnitAt(oldText.length - 1 - suffix) ==
              newText.codeUnitAt(newText.length - 1 - suffix)) {
        suffix++;
      }
      final removeStart = prefix;
      final removeEnd = oldText.length - suffix;
      final insertion = newText.substring(prefix, newText.length - suffix);

      final oldMatches = _tagRegex.allMatches(oldText).toList();

      bool isInTag(int pos) {
        for (final m in oldMatches) {
          if (m.start <= pos && m.end > pos) return true;
        }
        return false;
      }

      bool intersectsTag = false;
      for (final m in oldMatches) {
        if (m.start < removeEnd && m.end > removeStart) {
          intersectsTag = true;
          break;
        }
      }

      if (intersectsTag && insertion.isEmpty && removeEnd - removeStart == 1) {
        // Single-char backspace hitting a tag: walk left past tag(s)
        // and delete the first visible character instead.
        int cursor = removeStart;
        int? victim;
        while (cursor > 0) {
          final probe = cursor - 1;
          if (isInTag(probe)) {
            for (final m in oldMatches) {
              if (m.start <= probe && m.end > probe) {
                cursor = m.start;
                break;
              }
            }
          } else {
            victim = probe;
            break;
          }
        }
        if (victim != null) {
          newText = oldText.substring(0, victim) + oldText.substring(victim + 1);
          newSelection = TextSelection.collapsed(offset: victim);
        } else {
          return;
        }
      }
    }

    // Selection snapping: ensure start/end never land inside a tag.
    // Handles both LTR (base < extent) and RTL (base > extent) selections.
    if (newSelection.isValid && !newSelection.isCollapsed) {
      final matches = _tagRegex.allMatches(newText);
      int s = newSelection.start; // normalized min
      int e = newSelection.end;   // normalized max
      bool shifted = false;
      for (final m in matches) {
        if (s > m.start && s < m.end) { s = m.start; shifted = true; }
        if (e > m.start && e < m.end) { e = m.end; shifted = true; }
      }
      if (shifted) {
        // Preserve the original direction (RTL selections have base > extent)
        final isReversed = newSelection.baseOffset > newSelection.extentOffset;
        newSelection = newSelection.copyWith(
          baseOffset: isReversed ? e : s,
          extentOffset: isReversed ? s : e,
        );
      }
    } else if (newSelection.isCollapsed && newSelection.baseOffset > 0) {
      for (final m in _tagRegex.allMatches(newText)) {
        if (newSelection.baseOffset > m.start && newSelection.baseOffset < m.end) {
          final toStart = (newSelection.baseOffset - m.start).abs();
          final toEnd = (newSelection.baseOffset - m.end).abs();
          final target = (toStart <= toEnd) ? m.start : m.end;
          newSelection = TextSelection.collapsed(offset: target);
          break;
        }
      }
    }

    super.value = newValue.copyWith(text: newText, selection: newSelection);
  }

  static Color? _parseHex(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(v);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final src = text;
    TextSelection renderSelection;
    if (isGlobalSelected) {
      renderSelection = TextSelection(baseOffset: 0, extentOffset: src.length);
    } else if (externalSelection != null) {
      // externalSelection is authoritative whenever it is set:
      //   - range  → show amber highlight for that range
      //   - collapsed (offset: 0) → suppress all highlight (block is outside
      //     the global selection range). Do NOT fall through to the native
      //     controller.selection, which may hold a stale range from a prior
      //     user gesture and would leak an amber highlight.
      final s = externalSelection!.start;
      final e = externalSelection!.end;
      renderSelection = TextSelection(baseOffset: s, extentOffset: e);
    } else {
      // null → not in global-selection mode; show native cursor/selection.
      final s = selection.start.clamp(0, src.length);
      final e = selection.end.clamp(0, src.length);
      renderSelection = TextSelection(baseOffset: s, extentOffset: e);
    }

    // Style stack state
    bool bold = false;
    bool italic = false;
    bool underline = false;
    final List<Color> textColors = [];
    final List<Color> bgColors = [];
    final List<double> sizes = [];
    final List<String> fonts = [];

    TextStyle current() {
      TextStyle s = style ?? const TextStyle();
      if (bold) s = s.copyWith(fontWeight: FontWeight.bold);
      if (italic) s = s.copyWith(fontStyle: FontStyle.italic);
      if (underline) s = s.copyWith(decoration: TextDecoration.underline);
      if (textColors.isNotEmpty) s = s.copyWith(color: textColors.last);
      if (bgColors.isNotEmpty) s = s.copyWith(backgroundColor: bgColors.last);
      if (sizes.isNotEmpty) s = s.copyWith(fontSize: sizes.last);
      if (fonts.isNotEmpty) s = s.copyWith(fontFamily: fonts.last);
      return s;
    }

    final List<InlineSpan> children = [];

    void emitContent(int start, int end) {
      if (start >= end) return;
      final baseStyle = current();
      final hasSelection = !renderSelection.isCollapsed &&
          renderSelection.end > start &&
          renderSelection.start < end;
      if (!hasSelection) {
        children.add(TextSpan(text: src.substring(start, end), style: baseStyle));
        return;
      }
      final selStart = renderSelection.start.clamp(start, end);
      final selEnd = renderSelection.end.clamp(start, end);
      if (selStart > start) {
        children.add(TextSpan(text: src.substring(start, selStart), style: baseStyle));
      }
      children.add(TextSpan(
        text: src.substring(selStart, selEnd),
        style: baseStyle.copyWith(backgroundColor: _selectionBg),
      ));
      if (selEnd < end) {
        children.add(TextSpan(text: src.substring(selEnd, end), style: baseStyle));
      }
    }

    void emitTag(int start, int end) {
      if (start >= end) return;
      children.add(TextSpan(text: src.substring(start, end), style: _tagStyle));
    }

    int cursor = 0;
    for (final m in _tagRegex.allMatches(src)) {
      if (m.start > cursor) emitContent(cursor, m.start);
      final tag = m.group(0)!;
      emitTag(m.start, m.end);

      if (tag == '**') {
        bold = !bold;
      } else if (tag == '[u]') {
        underline = true;
      } else if (tag == '[/u]') {
        underline = false;
      } else if (tag == '[i]') {
        italic = true;
      } else if (tag == '[/i]') {
        italic = false;
      } else if (m.group(1) != null) {
        final c = _parseHex(m.group(1)!);
        if (c != null) textColors.add(c);
      } else if (tag == '[/color]') {
        if (textColors.isNotEmpty) textColors.removeLast();
      } else if (m.group(2) != null) {
        final c = _parseHex(m.group(2)!);
        if (c != null) bgColors.add(c);
      } else if (tag == '[/bg]') {
        if (bgColors.isNotEmpty) bgColors.removeLast();
      } else if (m.group(3) != null) {
        final s = double.tryParse(m.group(3)!);
        if (s != null) sizes.add(s);
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (m.group(4) != null) {
        fonts.add(m.group(4)!);
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      }
      // align/rtl/ltr tags: no inline style effect, already hidden.
      cursor = m.end;
    }
    if (cursor < src.length) emitContent(cursor, src.length);

    return TextSpan(style: style, children: children);
  }
}
