import 'package:flutter/material.dart';

// v3.9.5.60: Sovereign Styling Service
// ── Core Styling Engine ──────────────────────────────────────────────────────

class StylingService {
  static String stripTags(String text) {
    if (text.isEmpty) return '';
    // v3.9.5.56: Standardized Tag Extraction
    final regex = RegExp(r'\[\/?(u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
    return text.replaceAll(regex, '');
  }

  /// Alignment is paragraph-level and mutually exclusive.
  /// Strips ALL existing alignment tags from the entire text, then re-wraps.
  static String applyLayout(String text, TextSelection selection, String layout) {
    if (text.isEmpty) return text;

    // v3.9.5.60: Total-text reconciler — strip ALL alignment tags everywhere
    final clean = text.replaceAll(
      RegExp(r'\[\/?(center|left|right|rtl|ltr|align)(?:=[^\]]+)?\]'),
      '',
    );

    // 'left' is the baseline — no wrapping needed
    if (layout == 'left' || layout == 'ltr') {
      return clean;
    }

    return '[$layout]$clean[/$layout]';
  }

  // v3.9.5.64: Slices a text block while mathematically preserving and re-wrapping geometric tags
  static List<String> splitBlock(String currentText, int splitIndex) {
    final p1 = currentText.substring(0, splitIndex);
    final p2 = currentText.substring(splitIndex);

    final regex = RegExp(r'\*\*|\[\/?(?:u|i|size|font|color|bg|center|left|right|rtl|ltr|align)(?:=[^\]]+)?\]');
    final stack = <String>[];

    for (final match in regex.allMatches(p1)) {
      final tag = match.group(0)!;
      if (tag == '**') {
        if (stack.contains('**')) stack.remove('**');
        else stack.add('**');
      } else if (tag.startsWith('[/')) {
        final family = tag.substring(2, tag.indexOf(']'));
        for (int i = stack.length - 1; i >= 0; i--) {
          if (stack[i].startsWith('[$family')) {
            stack.removeAt(i);
            break;
          }
        }
      } else {
        stack.add(tag);
      }
    }

    String p1Suffix = '';
    String p2Prefix = '';

    for (final tag in stack) {
      String closeTag = '**';
      if (tag != '**') {
        final family = tag.contains('=') 
            ? tag.substring(1, tag.indexOf('=')) 
            : tag.substring(1, tag.indexOf(']'));
        closeTag = '[/$family]';
      }
      // Close tags must be appended in reverse order (done by prepending to suffix)
      p1Suffix = closeTag + p1Suffix;
      p2Prefix += tag;
    }

    return [p1 + p1Suffix, p2Prefix + p2];
  }

  /// Converts a block's inline markup to an HTML fragment, mirroring the
  /// style stack used by [MarkupController.buildTextSpan]. Each block is
  /// wrapped in a <p> whose text-align reflects any align/center/right tag.
  static String markupToHtml(String markup) {
    if (markup.isEmpty) return '<p></p>';

    final tagRegex = RegExp(
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

    String align = 'left';
    bool bold = false, italic = false, underline = false;
    final colors = <String>[];
    final bgs = <String>[];
    final sizes = <String>[];
    final fonts = <String>[];

    final buf = StringBuffer();

    String escape(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');

    void emit(String text) {
      if (text.isEmpty) return;
      final styles = <String>[];
      if (colors.isNotEmpty) styles.add('color:${colors.last}');
      if (bgs.isNotEmpty) styles.add('background-color:${bgs.last}');
      if (sizes.isNotEmpty) styles.add('font-size:${sizes.last}px');
      if (fonts.isNotEmpty) styles.add("font-family:'${fonts.last}'");
      String inner = escape(text);
      if (underline) inner = '<u>$inner</u>';
      if (italic) inner = '<i>$inner</i>';
      if (bold) inner = '<b>$inner</b>';
      if (styles.isNotEmpty) {
        inner = '<span style="${styles.join(';')}">$inner</span>';
      }
      buf.write(inner);
    }

    int cursor = 0;
    for (final m in tagRegex.allMatches(markup)) {
      if (m.start > cursor) emit(markup.substring(cursor, m.start));
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
        colors.add(m.group(1)!);
      } else if (tag == '[/color]') {
        if (colors.isNotEmpty) colors.removeLast();
      } else if (m.group(2) != null) {
        bgs.add(m.group(2)!);
      } else if (tag == '[/bg]') {
        if (bgs.isNotEmpty) bgs.removeLast();
      } else if (m.group(3) != null) {
        sizes.add(m.group(3)!);
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (m.group(4) != null) {
        fonts.add(m.group(4)!);
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      } else if (m.group(5) != null) {
        align = m.group(5)!;
      } else if (m.group(6) != null) {
        align = m.group(6)!;
      }
      cursor = m.end;
    }
    if (cursor < markup.length) emit(markup.substring(cursor));

    return '<p style="text-align:$align;margin:0">${buf.toString()}</p>';
  }
}

