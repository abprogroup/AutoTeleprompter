import 'package:flutter/material.dart';

import '../../services/markup_decoration_service.dart';

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

  /// Visible-text version of [externalSelection] for search/debug traces.
  ///
  /// Painting stays raw-offset based so it matches the real TextField layout,
  /// but visible offsets are still useful for search result bookkeeping and
  /// highlight trace diagnostics.
  TextSelection? externalVisibleSelection;

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

  static const int _hiddenTagPlaceholderCodeUnit = 0x2060; // WORD JOINER

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
      final minLen =
          oldText.length < newText.length ? oldText.length : newText.length;
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
          newText =
              oldText.substring(0, victim) + oldText.substring(victim + 1);
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
      int e = newSelection.end; // normalized max
      bool shifted = false;
      for (final m in matches) {
        if (s > m.start && s < m.end) {
          s = m.start;
          shifted = true;
        }
        if (e > m.start && e < m.end) {
          e = m.end;
          shifted = true;
        }
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
        if (newSelection.baseOffset > m.start &&
            newSelection.baseOffset < m.end) {
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

  // â”€â”€ Visual-offset conversion helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Tags occupy raw character positions but render at zero visible width.
  // These helpers let callers track selections by VISIBLE character count so
  // that inserting or removing tags (B/I/U/size/color/font) never shifts the
  // logical selection.

  /// Number of visible (non-tag) characters from the start of [text] up to
  /// (but not including) [rawOffset].
  /// Returns [from] walked backward past any trailing invisible markup tags.
  ///
  /// When navigating into a block from the right (e.g. arrowLeft cross-block),
  /// placing the cursor at [text.length] can trap it between the end of the
  /// raw string and the end of a trailing invisible tag. Flutter's default
  /// cursor-left then increments the position INTO the tag; MarkupController's
  /// value-setter snaps it back to the end of the tag â€” forever stuck.
  ///
  /// Placing the cursor at safeEndOffset instead lands just before those
  /// trailing tags, so the very next arrowLeft moves past a real character.
  static int safeEndOffset(String text, [int? from]) {
    var pos = from ?? text.length;
    if (pos <= 0) return 0;
    // Walk backward: if pos is exactly at the END of a tag, step to its start.
    bool moved = true;
    while (moved && pos > 0) {
      moved = false;
      for (final m in _tagRegex.allMatches(text)) {
        if (m.end == pos) {
          pos = m.start;
          moved = true;
          break;
        }
      }
    }
    return pos;
  }

  /// Returns a prefix string of opening markup tags that are active
  /// (unclosed) at [rawOffset] inside [text].
  ///
  /// When deleting a range `[0, rawOffset]` from the start of a block, the
  /// remaining text (`text.substring(rawOffset)`) loses any opening tags that
  /// were in the deleted range. Prepending `openTagsAt(text, rawOffset)` to
  /// the remaining text restores the style context so the cut doesn't wipe
  /// all formatting from the surviving portion of the block.
  static String openTagsAt(String text, int rawOffset) {
    if (rawOffset <= 0 || rawOffset > text.length) return '';
    final sub = text.substring(0, rawOffset);
    bool bold = false;
    bool italic = false;
    bool underline = false;
    final textColors = <String>[];
    final bgColors = <String>[];
    final sizes = <String>[];
    final fonts = <String>[];
    for (final m in _tagRegex.allMatches(sub)) {
      final tag = m.group(0)!;
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
        textColors.add('[color=${m.group(1)!}]');
      } else if (tag == '[/color]') {
        if (textColors.isNotEmpty) textColors.removeLast();
      } else if (m.group(2) != null) {
        bgColors.add('[bg=${m.group(2)!}]');
      } else if (tag == '[/bg]') {
        if (bgColors.isNotEmpty) bgColors.removeLast();
      } else if (m.group(3) != null) {
        sizes.add('[size=${m.group(3)!}]');
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (m.group(4) != null) {
        fonts.add('[font=${m.group(4)!}]');
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      }
    }
    final sb = StringBuffer();
    if (bold) sb.write('**');
    if (italic) sb.write('[i]');
    if (underline) sb.write('[u]');
    if (textColors.isNotEmpty) sb.write(textColors.last);
    if (bgColors.isNotEmpty) sb.write(bgColors.last);
    if (sizes.isNotEmpty) sb.write(sizes.last);
    if (fonts.isNotEmpty) sb.write(fonts.last);
    return sb.toString();
  }

  static int rawToVisualOffset(String text, int rawOffset) {
    return MarkupDecorationParser.rawToVisibleOffset(text, rawOffset);
  }

  /// Raw offset of the [visualOffset]-th visible character in [text].
  /// Returns [text.length] when [visualOffset] exceeds the visible char count.
  static int visualToRawOffset(String text, int visualOffset) {
    return MarkupDecorationParser.visibleToRawOffset(text, visualOffset);
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
      if (underline && !kUseCustomDocxDecorationPainting) {
        s = s.copyWith(decoration: TextDecoration.underline);
      }
      if (textColors.isNotEmpty) s = s.copyWith(color: textColors.last);
      if (bgColors.isNotEmpty && !kUseCustomDocxDecorationPainting) {
        s = s.copyWith(backgroundColor: bgColors.last);
      }
      if (sizes.isNotEmpty) s = s.copyWith(fontSize: sizes.last);
      if (fonts.isNotEmpty) s = s.copyWith(fontFamily: fonts.last);
      return s;
    }

    final List<InlineSpan> children = [];

    void emitContent(int start, int end) {
      if (start >= end) return;
      children.add(TextSpan(text: src.substring(start, end), style: current()));
    }

    void emitTag(int start, int end) {
      if (start >= end) return;
      // Keep the rendered span length identical to the raw markup tag length
      // so caret/selection offsets still map to controller.text, but avoid
      // painting literal hidden "[bg]" / "[align]" letters. Those invisible
      // LTR tag characters still participate in Unicode bidi layout and can
      // split RTL punctuation, underline, and DOCX highlight bands.
      children.add(TextSpan(
        text: String.fromCharCodes(List<int>.filled(
          end - start,
          _hiddenTagPlaceholderCodeUnit,
        )),
        style: _tagStyle,
      ));
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
