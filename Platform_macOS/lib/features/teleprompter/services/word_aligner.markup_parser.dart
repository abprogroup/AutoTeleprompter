part of 'word_aligner.dart';

List<_Span> _parseMarkup(String line) {
  return _parseMarkupRecursive(line, const _Span(''));
}

// Recursive markup parser â€” supports nested tags (e.g. **[rc]word[/rc]**)
List<_Span> _parseMarkupRecursive(String text, _Span base) {
  final spans = <_Span>[];
  final pattern = RegExp(
    r'\*\*(.*?)\*\*'
    r'|\[y\](.*?)\[\/y\]'
    r'|\[r\](.*?)\[\/r\]'
    r'|\[g\](.*?)\[\/g\]'
    r'|\[b\](.*?)\[\/b\]'
    r'|\[o\](.*?)\[\/o\]'
    r'|\[p\](.*?)\[\/p\]'
    r'|\[c\](.*?)\[\/c\]'
    r'|\[pk\](.*?)\[\/pk\]'
    r'|\[yc\](.*?)\[\/yc\]'
    r'|\[rc\](.*?)\[\/rc\]'
    r'|\[gc\](.*?)\[\/gc\]'
    r'|\[bc\](.*?)\[\/bc\]'
    r'|\[oc\](.*?)\[\/oc\]'
    r'|\[pc\](.*?)\[\/pc\]'
    r'|\[cc\](.*?)\[\/cc\]'
    r'|\[pkc\](.*?)\[\/pkc\]'
    r'|\[u\](.*?)\[\/u\]'
    r'|\[size=(\d+)\](.*?)\[\/size\]'
    r'|\[(center|left|right)\](.*?)\[\/\21\]'
    r'|\[align=(center|left|right)\](.*?)\[\/align=\23\]'
    r'|\[i\](.*?)\[\/i\]'
    r'|\[(rtl|ltr)\](.*?)\[\/\26\]'
    r'|\[color=([^\]]+)\](.*?)\[\/color\]'
    r'|\[bg=([^\]]+)\](.*?)\[\/bg\]',
    dotAll: true,
  );
  int last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(_Span(text.substring(last, m.start),
          isBold: base.isBold,
          isUnderline: base.isUnderline,
          fontSize: base.fontSize,
          alignment: base.alignment,
          isItalic: base.isItalic,
          isParagraphRtl: base.isParagraphRtl,
          highlight: base.highlight,
          textColor: base.textColor));
    }
    if (m.group(1) != null) {
      spans.addAll(_parseMarkupRecursive(
          m.group(1)!, base.copyWith(text: '', isBold: true)));
    } else if (m.group(2) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(2)!,
          base.copyWith(text: '', highlight: Colors.yellow.withOpacity(0.6))));
    } else if (m.group(3) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(3)!,
          base.copyWith(text: '', highlight: Colors.red.withOpacity(0.55))));
    } else if (m.group(4) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(4)!,
          base.copyWith(text: '', highlight: Colors.green.withOpacity(0.55))));
    } else if (m.group(5) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(5)!,
          base.copyWith(text: '', highlight: Colors.blue.withOpacity(0.45))));
    } else if (m.group(6) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(6)!,
          base.copyWith(text: '', highlight: Colors.orange.withOpacity(0.50))));
    } else if (m.group(7) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(7)!,
          base.copyWith(text: '', highlight: Colors.purple.withOpacity(0.45))));
    } else if (m.group(8) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(8)!,
          base.copyWith(text: '', highlight: Colors.cyan.withOpacity(0.45))));
    } else if (m.group(9) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(9)!,
          base.copyWith(text: '', highlight: Colors.pink.withOpacity(0.45))));
    } else if (m.group(10) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(10)!,
          base.copyWith(text: '', textColor: Colors.yellow.shade300)));
    } else if (m.group(11) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(11)!,
          base.copyWith(text: '', textColor: Colors.red.shade300)));
    } else if (m.group(12) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(12)!,
          base.copyWith(text: '', textColor: Colors.greenAccent.shade200)));
    } else if (m.group(13) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(13)!,
          base.copyWith(text: '', textColor: Colors.blue.shade300)));
    } else if (m.group(14) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(14)!,
          base.copyWith(text: '', textColor: Colors.orange.shade300)));
    } else if (m.group(15) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(15)!,
          base.copyWith(text: '', textColor: Colors.purple.shade200)));
    } else if (m.group(16) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(16)!,
          base.copyWith(text: '', textColor: Colors.cyan.shade300)));
    } else if (m.group(17) != null) {
      spans.addAll(_parseMarkupRecursive(m.group(17)!,
          base.copyWith(text: '', textColor: Colors.pink.shade300)));
    } else if (m.group(18) != null) {
      spans.addAll(_parseMarkupRecursive(
          m.group(18)!, base.copyWith(text: '', isUnderline: true)));
    } else if (m.group(19) != null && m.group(20) != null) {
      final sz = double.tryParse(m.group(19)!);
      spans.addAll(_parseMarkupRecursive(
          m.group(20)!, base.copyWith(text: '', fontSize: sz)));
    } else if (m.group(21) != null && m.group(22) != null) {
      // [center|left|right] legacy format
      final alignStr = m.group(21)!;
      TextAlign align = TextAlign.center;
      if (alignStr == 'left') align = TextAlign.left;
      if (alignStr == 'right') align = TextAlign.right;
      spans.addAll(_parseMarkupRecursive(
          m.group(22)!, base.copyWith(text: '', alignment: align)));
    } else if (m.group(23) != null && m.group(24) != null) {
      // [align=center|left|right] current editor format
      final alignStr = m.group(23)!;
      TextAlign align = TextAlign.center;
      if (alignStr == 'left') align = TextAlign.left;
      if (alignStr == 'right') align = TextAlign.right;
      spans.addAll(_parseMarkupRecursive(
          m.group(24)!, base.copyWith(text: '', alignment: align)));
    } else if (m.group(25) != null) {
      // [i] italics
      spans.addAll(_parseMarkupRecursive(
          m.group(25)!, base.copyWith(text: '', isItalic: true)));
    } else if (m.group(26) != null && m.group(27) != null) {
      // [rtl|ltr]
      final dir = m.group(26)!;
      spans.addAll(_parseMarkupRecursive(
          m.group(27)!, base.copyWith(text: '', isParagraphRtl: dir == 'rtl')));
    } else if (m.group(28) != null && m.group(29) != null) {
      // [color=#HEX] custom text color
      final c = _parseHexColor(m.group(28)!);
      if (c != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(29)!, base.copyWith(text: '', textColor: c)));
      } else {
        spans.addAll(_parseMarkupRecursive(m.group(29)!, base));
      }
    } else if (m.group(30) != null && m.group(31) != null) {
      // [bg=#HEX] custom highlight/background color
      final c = _parseHexColor(m.group(30)!);
      if (c != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(31)!, base.copyWith(text: '', highlight: c)));
      } else {
        spans.addAll(_parseMarkupRecursive(m.group(31)!, base));
      }
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(_Span(text.substring(last),
        isBold: base.isBold,
        isUnderline: base.isUnderline,
        fontSize: base.fontSize,
        alignment: base.alignment,
        isParagraphRtl: base.isParagraphRtl,
        isItalic: base.isItalic,
        highlight: base.highlight,
        textColor: base.textColor));
  }
  return spans;
}

/// Parse a hex color string like "#FF0000" or "FF0000" into a Color.
Color? _parseHexColor(String raw) {
  var hex = raw.trim().replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(v);
}

// â”€â”€ Aligner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Core alignment: given a script word list and a speech transcript,
/// determine which word the user has reached.
///
/// Strategy:
/// 1. FAST PATH: Check the very next expected word(s) first â€” if the last
///    spoken word matches the next script word, advance by exactly 1.
/// 2. NEARBY SCAN: Check a small window (Â±8 words) for a strong single-word
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

  _Span copyWith({
    String? text,
    bool? isBold,
    bool? isUnderline,
    double? fontSize,
    TextAlign? alignment,
    bool? isItalic,
    bool? isParagraphRtl,
    Color? highlight,
    Color? textColor,
  }) {
    return _Span(
      text ?? this.text,
      isBold: isBold ?? this.isBold,
      isUnderline: isUnderline ?? this.isUnderline,
      fontSize: fontSize ?? this.fontSize,
      alignment: alignment ?? this.alignment,
      isItalic: isItalic ?? this.isItalic,
      isParagraphRtl: isParagraphRtl ?? this.isParagraphRtl,
      highlight: highlight ?? this.highlight,
      textColor: textColor ?? this.textColor,
    );
  }
}
