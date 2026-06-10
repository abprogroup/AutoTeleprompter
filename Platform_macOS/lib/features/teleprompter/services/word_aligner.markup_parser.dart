part of 'word_aligner.dart';

/// Stack-based markup parser. Mirrors the editor's decoration parser:
/// open/close tags push/pop independent style stacks, so OVERLAPPING (not
/// strictly nested) tags — e.g. `[bg=..]x[/size][/font][font=..][size=..][/bg]`
/// produced by the editor when a highlight crosses size/font runs — still
/// apply correctly. The previous recursive pair-matching parser dropped the
/// highlight in those cases (it matched [size]..[/size] first, splitting the
/// [bg] open away from its [/bg]); that was the legacy/imported-file highlight
/// bug fixed on Windows (BUG-012) and ported here.
List<_Span> _parseMarkup(String line) {
  final spans = <_Span>[];
  var bold = false;
  var underline = false;
  var italic = false;
  final sizes = <double>[];
  final aligns = <TextAlign>[];
  final rtls = <bool>[];
  final highlights = <Color>[];
  final textColors = <Color>[];

  void emit(String text) {
    if (text.isEmpty) return;
    spans.add(_Span(
      text,
      isBold: bold,
      isUnderline: underline,
      isItalic: italic,
      fontSize: sizes.isEmpty ? null : sizes.last,
      alignment: aligns.isEmpty ? null : aligns.last,
      isParagraphRtl: rtls.isEmpty ? null : rtls.last,
      highlight: highlights.isEmpty ? null : highlights.last,
      textColor: textColors.isEmpty ? null : textColors.last,
    ));
  }

  void popStack(List<dynamic> stack) {
    if (stack.isNotEmpty) stack.removeLast();
  }

  var cursor = 0;
  for (final m in _spanTagRegex.allMatches(line)) {
    emit(line.substring(cursor, m.start));
    cursor = m.end;
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
    } else if (tag.startsWith('[size=')) {
      final v = double.tryParse(tag.substring(6, tag.length - 1));
      if (v != null) sizes.add(v);
    } else if (tag == '[/size]') {
      popStack(sizes);
    } else if (tag.startsWith('[align=')) {
      aligns.add(_alignFromName(tag.substring(7, tag.length - 1)));
    } else if (tag == '[center]') {
      aligns.add(TextAlign.center);
    } else if (tag == '[left]') {
      aligns.add(TextAlign.left);
    } else if (tag == '[right]') {
      aligns.add(TextAlign.right);
    } else if (tag.startsWith('[/align') ||
        tag == '[/center]' ||
        tag == '[/left]' ||
        tag == '[/right]') {
      popStack(aligns);
    } else if (tag == '[rtl]') {
      rtls.add(true);
    } else if (tag == '[ltr]') {
      rtls.add(false);
    } else if (tag == '[/rtl]' || tag == '[/ltr]') {
      popStack(rtls);
    } else if (tag.startsWith('[color=')) {
      final c = _parseHexColor(tag.substring(7, tag.length - 1));
      if (c != null) textColors.add(c);
    } else if (tag == '[/color]') {
      popStack(textColors);
    } else if (tag.startsWith('[bg=')) {
      final c = _parseHexColor(tag.substring(4, tag.length - 1));
      if (c != null) highlights.add(c);
    } else if (tag == '[/bg]') {
      popStack(highlights);
    } else if (tag.startsWith('[font=') || tag == '[/font]') {
      // Font family is visual-only metadata; consume but do not style words.
    } else if (tag.startsWith('[/')) {
      // Shorthand close: [/y].. (highlight) or [/yc].. (text color).
      final name = tag.substring(2, tag.length - 1);
      if (_shorthandHighlight(name) != null) {
        popStack(highlights);
      } else if (_shorthandTextColor(name) != null) {
        popStack(textColors);
      }
    } else {
      // Shorthand open: [y].. (highlight) or [yc].. (text color).
      final name = tag.substring(1, tag.length - 1);
      final hl = _shorthandHighlight(name);
      final tc = _shorthandTextColor(name);
      if (hl != null) {
        highlights.add(hl);
      } else if (tc != null) {
        textColors.add(tc);
      }
    }
  }
  emit(line.substring(cursor));
  return spans;
}

TextAlign _alignFromName(String name) {
  switch (name) {
    case 'left':
      return TextAlign.left;
    case 'right':
      return TextAlign.right;
    default:
      return TextAlign.center;
  }
}

Color? _shorthandHighlight(String name) {
  switch (name) {
    case 'y':
      return Colors.yellow.withValues(alpha: 0.6);
    case 'r':
      return Colors.red.withValues(alpha: 0.55);
    case 'g':
      return Colors.green.withValues(alpha: 0.55);
    case 'b':
      return Colors.blue.withValues(alpha: 0.45);
    case 'o':
      return Colors.orange.withValues(alpha: 0.50);
    case 'p':
      return Colors.purple.withValues(alpha: 0.45);
    case 'c':
      return Colors.cyan.withValues(alpha: 0.45);
    case 'pk':
      return Colors.pink.withValues(alpha: 0.45);
  }
  return null;
}

Color? _shorthandTextColor(String name) {
  switch (name) {
    case 'yc':
      return Colors.yellow.shade300;
    case 'rc':
      return Colors.red.shade300;
    case 'gc':
      return Colors.greenAccent.shade200;
    case 'bc':
      return Colors.blue.shade300;
    case 'oc':
      return Colors.orange.shade300;
    case 'pc':
      return Colors.purple.shade200;
    case 'cc':
      return Colors.cyan.shade300;
    case 'pkc':
      return Colors.pink.shade300;
  }
  return null;
}

// Matches every open/close markup tag, longest alternatives first so e.g.
// `[center]` is not mis-read as shorthand `[c]`.
final RegExp _spanTagRegex = RegExp(
  r'\*\*'
  r'|\[\/?(?:center|left|right|rtl|ltr|pkc|pk|yc|rc|gc|bc|oc|pc|cc|y|r|g|b|o|p|c|u|i)\]'
  r'|\[size=\d+(?:\.\d+)?\]|\[\/size\]'
  r'|\[align=(?:center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
  r'|\[color=[^\]]+\]|\[\/color\]'
  r'|\[bg=[^\]]+\]|\[\/bg\]'
  r'|\[font=[^\]]+\]|\[\/font\]',
);

/// Rewrites [text] so every markup tag opens and closes on the same line.
/// Tags still open at a line end are closed there and re-opened at the start
/// of the next non-blank line, so a highlight/color/style spanning a line
/// break survives the per-line parser. Well-formed single-line content is
/// returned unchanged; blank lines stay blank (preserving hard breaks).
String _balanceLineSpanningTags(String text) {
  final hasTags = text.contains('[') || text.contains('**');
  if (!text.contains('\n') || !hasTags) return text;
  final lines = text.split('\n');
  final open = <String>[]; // active openers, outermost first
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      // Keep blank paragraphs blank; the open-tag stack carries through.
      out.add(line);
      continue;
    }
    final sb = StringBuffer();
    for (final opener in open) {
      sb.write(opener);
    }
    var cursor = 0;
    for (final m in _balanceTagRegex.allMatches(line)) {
      sb.write(line.substring(cursor, m.start));
      final tag = m.group(0)!;
      sb.write(tag);
      if (tag == '**') {
        final idx = open.lastIndexOf('**');
        if (idx >= 0) {
          open.removeAt(idx);
        } else {
          open.add('**');
        }
      } else if (tag.startsWith('[/')) {
        final name = _tagName(tag);
        final idx = open.lastIndexWhere((o) => _tagName(o) == name);
        if (idx >= 0) open.removeAt(idx);
      } else {
        open.add(tag);
      }
      cursor = m.end;
    }
    sb.write(line.substring(cursor));
    for (var i = open.length - 1; i >= 0; i--) {
      sb.write(_closerFor(open[i]));
    }
    out.add(sb.toString());
  }
  return out.join('\n');
}

/// The identifying name of an open/close tag (e.g. `bg`, `align`, `y`).
String _tagName(String tag) {
  if (tag == '**') return '**';
  var inner = tag;
  if (inner.startsWith('[/')) {
    inner = inner.substring(2, inner.length - 1);
  } else if (inner.startsWith('[')) {
    inner = inner.substring(1, inner.length - 1);
  }
  final eq = inner.indexOf('=');
  return eq >= 0 ? inner.substring(0, eq) : inner;
}

/// The closing tag for a given opener (align keeps its value).
String _closerFor(String opener) {
  if (opener == '**') return '**';
  final inner = opener.substring(1, opener.length - 1);
  final eq = inner.indexOf('=');
  if (eq < 0) return '[/$inner]';
  final name = inner.substring(0, eq);
  return name == 'align' ? '[/$inner]' : '[/$name]';
}

final RegExp _balanceTagRegex = RegExp(
  r'\*\*'
  r'|\[\/?(?:center|left|right|rtl|ltr|pkc|pk|yc|rc|gc|bc|oc|pc|cc|y|r|g|b|o|p|c|u|i)\]'
  r'|\[size=\d+(?:\.\d+)?\]|\[\/size\]'
  r'|\[align=(?:center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
  r'|\[color=[^\]]+\]|\[\/color\]'
  r'|\[bg=[^\]]+\]|\[\/bg\]'
  r'|\[font=[^\]]+\]|\[\/font\]',
);

/// Parse a hex color string like "#FF0000" or "FF0000" into a Color.
Color? _parseHexColor(String raw) {
  var hex = raw.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(v);
}

// ── Aligner ──────────────────────────────────────────────────────────────────

/// Core alignment: given a script word list and a speech transcript,
/// determine which word the user has reached.
///
/// Strategy:
/// 1. FAST PATH: Check the very next expected word(s) first — if the last
///    spoken word matches the next script word, advance by exactly 1.
/// 2. NEARBY SCAN: Check a small window (±8 words) for a strong single-word
///    match. This handles minor improvisation where the user skips 1-2 words.
/// 3. MULTI-WORD CONFIRMATION: Use the last 3 spoken words to confirm a
///    position via sequence alignment. This prevents false matches on common
///    words appearing multiple times.
///

class _Span {
  final String text;
  final bool isBold;
  final bool isUnderline;
  final double? fontSize;
  final TextAlign? alignment;
  final bool isItalic;
  final bool? isParagraphRtl;
  final Color? highlight;
  final Color? textColor;

  const _Span(
    this.text, {
    this.isBold = false,
    this.isUnderline = false,
    this.fontSize,
    this.alignment,
    this.isItalic = false,
    this.isParagraphRtl,
    this.highlight,
    this.textColor,
  });
}
