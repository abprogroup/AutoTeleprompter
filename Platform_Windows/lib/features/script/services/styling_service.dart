import 'package:flutter/material.dart';

import 'markup_decoration_service.dart';

// v3.9.5.60: Sovereign Styling Service
// ── Core Styling Engine ──────────────────────────────────────────────────────

class StylingService {
  static String stripTags(String text) {
    if (text.isEmpty) return '';
    // v3.9.5.56: Standardized Tag Extraction
    final regex = RegExp(
        r'\[\/?(u|i|center|left|right|rtl|ltr|color|bg|font|align|size)(?:=[^\]]+)?\]|\*\*');
    return text.replaceAll(regex, '');
  }

  /// Stable visible-style signature used for editor history cancellation.
  ///
  /// Raw inline markup can legitimately normalize while a user toggles a style
  /// on and back off during one open toolbar session. History should treat that
  /// as a canceled action when the visible text and effective visible styles are
  /// back at the baseline.
  static String semanticStyleSignature(String text) {
    if (text.isEmpty) return '';

    final buffer = StringBuffer();
    var bold = false;
    var underline = false;
    var italic = false;
    final colors = <String>[];
    final backgrounds = <String>[];
    final sizes = <String>[];
    final fonts = <String>[];
    final aligns = <String>[];
    final directions = <String>[];

    String styleKey() => [
          bold ? 'b1' : 'b0',
          underline ? 'u1' : 'u0',
          italic ? 'i1' : 'i0',
          colors.isEmpty ? 'c=' : 'c=${colors.last}',
          backgrounds.isEmpty ? 'bg=' : 'bg=${backgrounds.last}',
          sizes.isEmpty ? 's=' : 's=${sizes.last}',
          fonts.isEmpty ? 'f=' : 'f=${fonts.last}',
          aligns.isEmpty ? 'a=' : 'a=${aligns.last}',
          directions.isEmpty ? 'd=' : 'd=${directions.last}',
        ].join('|');

    void emit(String visibleText) {
      if (visibleText.isEmpty) return;
      buffer
        ..write(styleKey())
        ..write('\u001f')
        ..write(visibleText)
        ..write('\u001e');
    }

    var cursor = 0;
    for (final match in MarkupDecorationParser.tagRegex.allMatches(text)) {
      if (match.start > cursor) emit(text.substring(cursor, match.start));
      final tag = match.group(0)!;
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
      } else if (tag.startsWith('[color=')) {
        colors.add(tag.substring('[color='.length, tag.length - 1));
      } else if (tag == '[/color]') {
        if (colors.isNotEmpty) colors.removeLast();
      } else if (tag.startsWith('[bg=')) {
        backgrounds.add(tag.substring('[bg='.length, tag.length - 1));
      } else if (tag == '[/bg]') {
        if (backgrounds.isNotEmpty) backgrounds.removeLast();
      } else if (tag.startsWith('[size=')) {
        sizes.add(tag.substring('[size='.length, tag.length - 1));
      } else if (tag == '[/size]') {
        if (sizes.isNotEmpty) sizes.removeLast();
      } else if (tag.startsWith('[font=')) {
        fonts.add(tag.substring('[font='.length, tag.length - 1));
      } else if (tag == '[/font]') {
        if (fonts.isNotEmpty) fonts.removeLast();
      } else if (tag.startsWith('[align=')) {
        aligns.add(tag.substring('[align='.length, tag.length - 1));
      } else if (tag.startsWith('[/align')) {
        if (aligns.isNotEmpty) aligns.removeLast();
      } else if (tag == '[center]' || tag == '[left]' || tag == '[right]') {
        aligns.add(tag.substring(1, tag.length - 1));
      } else if (tag == '[/center]' ||
          tag == '[/left]' ||
          tag == '[/right]') {
        if (aligns.isNotEmpty) aligns.removeLast();
      } else if (tag == '[rtl]' || tag == '[ltr]') {
        directions.add(tag.substring(1, tag.length - 1));
      } else if (tag == '[/rtl]' || tag == '[/ltr]') {
        if (directions.isNotEmpty) directions.removeLast();
      }
      cursor = match.end;
    }
    if (cursor < text.length) emit(text.substring(cursor));
    return buffer.toString();
  }

  static String recentScriptPreviewText({
    required String fullText,
    String? snippet,
  }) {
    final explicitSnippet = snippet == null
        ? ''
        : stripTags(snippet).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (explicitSnippet.isNotEmpty) return explicitSnippet;

    final lines = fullText
        .split('\n')
        .map((line) => stripTags(line).replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .take(2)
        .toList();
    if (lines.isEmpty) return 'No content preview';
    return lines.join('\n');
  }

  /// Alignment is paragraph-level and mutually exclusive.
  /// Strips existing alignment tags from the entire text, then re-wraps.
  static String applyLayout(
      String text, TextSelection selection, String layout) {
    if (text.isEmpty) return text;

    // Strip alignment only; RTL/LTR tags are handled by applyDirection.
    final clean = text.replaceAll(
      RegExp(
        r'\[(?:align=)?(?:center|left|right)\]'
        r'|\[\/(?:align=)?(?:center|left|right)\]',
      ),
      '',
    );

    // Always wrap with explicit tags so teleprompter can detect alignment.
    return '[$layout]$clean[/$layout]';
  }

  /// Direction is paragraph-level and mutually exclusive.
  /// Strips only direction tags from the entire text, then re-wraps.
  static String applyDirection(
      String text, TextSelection selection, String direction) {
    if (text.isEmpty) return text;
    if (direction != 'rtl' && direction != 'ltr') return text;

    final clean = text.replaceAll(
      RegExp(r'\[(?:rtl|ltr)\]|\[\/(?:rtl|ltr)\]'),
      '',
    );

    return '[$direction]$clean[/$direction]';
  }

  // v3.9.5.64: Slices a text block while mathematically preserving and re-wrapping geometric tags
  static List<String> splitBlock(String currentText, int splitIndex) {
    final p1 = currentText.substring(0, splitIndex);
    final p2 = currentText.substring(splitIndex);

    final regex = RegExp(
        r'\*\*|\[\/?(?:u|i|size|font|color|bg|center|left|right|rtl|ltr|align)(?:=[^\]]+)?\]');
    final stack = <String>[];

    for (final match in regex.allMatches(p1)) {
      final tag = match.group(0)!;
      if (tag == '**') {
        if (stack.contains('**')) {
          stack.remove('**');
        } else {
          stack.add('**');
        }
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
