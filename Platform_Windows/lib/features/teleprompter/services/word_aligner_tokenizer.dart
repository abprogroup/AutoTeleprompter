part of 'word_aligner.dart';

class _WordAlignerTokenizer {
  /// Parse raw script text into a list of ScriptWords.
  /// Preserves paragraph breaks as isNewline=true entries.
  static List<ScriptWord> tokenize(String text) {
    final words = <ScriptWord>[];
    int index = 0;

    // Heal markup tags that span a line break before the per-line parse.
    // The editor renders highlights/colors with a tolerant stack-based parser,
    // so a [bg=#hex] left open across a paragraph split still paints to the end
    // of the block. The per-line markup parser below needs a matching open+close
    // on the SAME line, so without this pass those cross-line highlights vanish
    // in present mode (the legacy/imported-file bug). Balancing re-opens active
    // tags at the start of each line and closes them at its end.
    final lines = _balanceLineSpanningTags(text).split('\n');

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];

      if (line.trim().isEmpty) {
        words.add(ScriptWord(
          raw: '\n\n', // v3.9.5.5: Hard break marker
          normalized: '',
          index: index++,
          isRtl: false,
          isNewline: true,
        ));
      } else {
        final parsed = _parseMarkup(line);
        final lineIsOptionalCue = _isProductionCueLine(line);
        var visiblePartIndex = 0;

        for (final token in parsed) {
          final clean = token.text.trim();
          if (clean.isEmpty) continue;

          final parts =
              _mergeStandaloneNeutralParts(clean.split(RegExp(r'\s+')));
          for (final part in parts) {
            if (part.isEmpty) continue;
            // v3.9.7: Strip residual markup tags before RTL detection AND normalization
            // so [color=#HEX] etc. don't dilute the Hebrew character ratio
            final cleanPart = part.replaceAll(
                RegExp(
                    r'\[\/?(u|i|color|bg|font|size|align|center|left|right|rtl|ltr)(?:=[^\]]+)?\]|\*\*'),
                '');
            final isRtl = cleanPart.isHebrew;
            final optionalCue = lineIsOptionalCue ||
                _isLeadingSpeakerLabel(cleanPart, visiblePartIndex);
            final normalized = cleanPart.normalizeForMatching();
            if (normalized.isEmpty &&
                _isStandaloneNeutralPunctuation(cleanPart)) {
              continue;
            }
            if (normalized.isEmpty && cleanPart.trim().isEmpty) continue;
            visiblePartIndex++;
            words.add(ScriptWord(
              raw: part,
              normalized: normalized,
              index: index++,
              isRtl: isRtl,
              isBold: token.isBold,
              isUnderline: token.isUnderline,
              fontSize: token.fontSize,
              alignment: token.alignment,
              isItalic: token.isItalic,
              isParagraphRtl: token.isParagraphRtl,
              highlight: token.highlight,
              textColor: token.textColor,
              isOptionalCue: optionalCue,
            ));
          }
        }

        // v3.9.5.3: Preserve single newlines as paragraph breaks
        if (li < lines.length - 1) {
          words.add(ScriptWord(
            raw: '\n', // v3.9.5.5: Soft break marker
            normalized: '',
            index: index++,
            isRtl: false,
            isNewline: true,
          ));
        }
      }
    }
    return words;
  }

  static bool _isProductionCueLine(String line) {
    final visible = line
        .replaceAll(
            RegExp(
                r'\[\/?(u|i|color|bg|font|size|align|center|left|right|rtl|ltr|y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc)(?:=[^\]]+)?\]|\*\*'),
            ' ')
        .trim();
    if (visible.isEmpty) return false;
    if (_isBracketedProductionCue(visible)) return true;

    final parts = _mergeStandaloneNeutralParts(visible.split(RegExp(r'\s+')));
    final normalized = parts
        .map((part) => part.normalizeForMatching())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty || normalized.length > 12) return false;

    final hasTechnicalCue =
        normalized.any((part) => _technicalCueMarkers.contains(part));
    if (hasTechnicalCue) return true;

    final rawLower = visible.toLowerCase();
    if (RegExp(r'(^|\s)(music|cue)\s*:').hasMatch(rawLower)) return true;
    if (RegExp(r'(^|\s)\u05de\u05d5\u05d6\u05d9\u05e7\u05d4\s*:')
        .hasMatch(visible)) {
      return true;
    }

    return false;
  }

  static bool _isBracketedProductionCue(String visible) {
    final trimmed = _stripCuePrefix(visible.trim());
    if (trimmed.isEmpty) return false;

    final bracketed =
        RegExp(r'^(?:[\[\(][^\]\)]+[\]\)]\s*)+$').hasMatch(trimmed);
    if (!bracketed) return false;

    final letters = RegExp(r'[A-Za-z]').allMatches(trimmed).length;
    final lowercase = RegExp(r'[a-z]').hasMatch(trimmed);
    final content = trimmed
        .replaceAll(RegExp(r'[\[\]\(\)]'), ' ')
        .trim()
        .normalizeForMatching();
    if (content.isEmpty) return false;
    final words = content.split(RegExp(r'\s+'));
    if (words.length > 14) return false;

    if (letters > 0 && !lowercase) return true;
    return words.any(_bracketedCueMarkers.contains);
  }

  static String _stripCuePrefix(String visible) {
    var current = visible;
    while (current.isNotEmpty) {
      final stripped = current.replaceFirst(
        RegExp(r'^\s*(?:[\u00bb>]|[-\u2010-\u2015]+|[\u2022\u25aa\u25cf])\s*'),
        '',
      );
      if (stripped == current) return current;
      current = stripped;
    }
    return current;
  }

  static bool _isLeadingSpeakerLabel(String text, int visiblePartIndex) {
    if (visiblePartIndex != 0) return false;
    final trimmed = text.trim();
    if (!trimmed.endsWith(':')) return false;
    final label =
        trimmed.substring(0, trimmed.length - 1).normalizeForMatching();
    if (label.isEmpty || label.length > 24) return false;
    return RegExp(r'[\u0590-\u05FFA-Za-z]').hasMatch(label);
  }

  static const Set<String> _technicalCueMarkers = {
    'vtr',
    'vt',
    'sot',
    'vo',
    'cg',
  };

  static const Set<String> _bracketedCueMarkers = {
    'applause',
    'beat',
    'broll',
    'camera',
    'cam',
    'cue',
    'cut',
    'graphic',
    'hold',
    'look',
    'music',
    'pause',
    'shot',
    'smile',
  };

  static List<String> _mergeStandaloneNeutralParts(Iterable<String> parts) {
    final merged = <String>[];
    var pendingOpen = '';
    for (final part in parts) {
      if (part.isEmpty) continue;
      var current = part;
      final trailingDash = _takeTrailingDashAfterClosingNeutral(current);
      if (trailingDash != null) {
        current = current.substring(0, current.length - trailingDash.length);
      }
      if (current.isNotEmpty && _isStandaloneOpeningNeutral(current)) {
        pendingOpen += current;
        if (trailingDash != null) pendingOpen += '$trailingDash ';
        continue;
      }
      if (current.isNotEmpty && _isStandaloneDashPrefix(current)) {
        pendingOpen += '$current ';
        if (trailingDash != null) pendingOpen += '$trailingDash ';
        continue;
      }
      if (current.isNotEmpty &&
          _isStandaloneClosingNeutral(current) &&
          merged.isNotEmpty) {
        merged[merged.length - 1] = merged.last + current;
        if (trailingDash != null) pendingOpen += '$trailingDash ';
        continue;
      }
      if (current.isNotEmpty) {
        merged.add(pendingOpen + current);
        pendingOpen = '';
      }
      if (trailingDash != null) {
        pendingOpen += '$trailingDash ';
      }
    }
    if (pendingOpen.isNotEmpty && merged.isNotEmpty) {
      if (RegExp(r'[-\u2010-\u2015]\s*$').hasMatch(pendingOpen)) {
        merged.add(pendingOpen.trimRight());
      } else {
        merged[merged.length - 1] = merged.last + pendingOpen;
      }
    } else if (pendingOpen.isNotEmpty) {
      merged.add(pendingOpen.trimRight());
    }
    return merged;
  }

  static String? _takeTrailingDashAfterClosingNeutral(String text) {
    final match = RegExp(r'[\]\)\}\?!\.,:;]+([-\u2010-\u2015]+)$')
        .firstMatch(text.trimRight());
    return match?.group(1);
  }

  static bool _isStandaloneDashPrefix(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[-\u2010-\u2015]+$').hasMatch(trimmed);
  }

  static bool _isStandaloneNeutralPunctuation(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\[\]\(\)\{\}\.,:;!?]+$').hasMatch(trimmed);
  }

  static bool _isStandaloneOpeningNeutral(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty && RegExp(r'^[\[\(\{]+$').hasMatch(trimmed);
  }

  static bool _isStandaloneClosingNeutral(String text) {
    final trimmed = text.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\]\)\}\.,:;!?]+$').hasMatch(trimmed);
  }

  // ── Markup parser ───────────────────────────────────────────────────────────

  /// Stack-based markup parser. Mirrors the editor's MarkupDecorationParser:
  /// open/close tags push/pop independent style stacks, so OVERLAPPING (not
  /// strictly nested) tags — e.g. `[bg=..]x[/size][/font][font=..][size=..][/bg]`
  /// produced by the editor when a highlight crosses size/font boundaries —
  /// still apply correctly. The previous recursive pair-matching parser dropped
  /// the highlight in those cases (it matched [size]..[/size] first, splitting
  /// the [bg] open away from its [/bg]); that was the legacy/imported-file bug.
  static List<_Span> _parseMarkup(String line) {
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

    void pop(List<dynamic> stack) {
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
        pop(sizes);
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
        pop(aligns);
      } else if (tag == '[rtl]') {
        rtls.add(true);
      } else if (tag == '[ltr]') {
        rtls.add(false);
      } else if (tag == '[/rtl]' || tag == '[/ltr]') {
        pop(rtls);
      } else if (tag.startsWith('[color=')) {
        final c = _parseHexColor(tag.substring(7, tag.length - 1));
        if (c != null) textColors.add(c);
      } else if (tag == '[/color]') {
        pop(textColors);
      } else if (tag.startsWith('[bg=')) {
        final c = _parseHexColor(tag.substring(4, tag.length - 1));
        if (c != null) highlights.add(c);
      } else if (tag == '[/bg]') {
        pop(highlights);
      } else if (tag.startsWith('[font=') || tag == '[/font]') {
        // Font family is visual-only metadata; consume but do not style words.
      } else if (tag.startsWith('[/')) {
        // Shorthand close: [/y].. (highlight) or [/yc].. (text color).
        final name = tag.substring(2, tag.length - 1);
        if (_shorthandHighlight(name) != null) {
          pop(highlights);
        } else if (_shorthandTextColor(name) != null) {
          pop(textColors);
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

  static TextAlign _alignFromName(String name) {
    switch (name) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  static Color? _shorthandHighlight(String name) {
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

  static Color? _shorthandTextColor(String name) {
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
  static final RegExp _spanTagRegex = RegExp(
    r'\*\*'
    r'|\[\/?(?:center|left|right|rtl|ltr|pkc|pk|yc|rc|gc|bc|oc|pc|cc|y|r|g|b|o|p|c|u|i)\]'
    r'|\[size=\d+(?:\.\d+)?\]|\[\/size\]'
    r'|\[align=(?:center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[color=[^\]]+\]|\[\/color\]'
    r'|\[bg=[^\]]+\]|\[\/bg\]'
    r'|\[font=[^\]]+\]|\[\/font\]',
  );

  // Matches every open/close markup tag the per-line parser understands.
  static final RegExp _balanceTagRegex = RegExp(
    r'\*\*'
    r'|\[\/?(?:y|r|g|b|o|p|c|pk|yc|rc|gc|bc|oc|pc|cc|pkc|u|i|rtl|ltr|center|left|right)\]'
    r'|\[size=\d+(?:\.\d+)?\]|\[\/size\]'
    r'|\[align=(?:center|left|right)\]|\[\/align(?:=(?:center|left|right))?\]'
    r'|\[color=[^\]]+\]|\[\/color\]'
    r'|\[bg=[^\]]+\]|\[\/bg\]'
    r'|\[font=[^\]]+\]|\[\/font\]',
  );

  /// Rewrites [text] so every markup tag opens and closes on the same line.
  /// Tags still open at a line end are closed there and re-opened at the start
  /// of the next non-blank line, so a highlight/color/style spanning a line
  /// break survives the per-line markup parser. Well-formed single-line content
  /// is returned unchanged. Blank lines stay blank (preserving hard breaks).
  static String _balanceLineSpanningTags(String text) {
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
  static String _tagName(String tag) {
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
  static String _closerFor(String opener) {
    if (opener == '**') return '**';
    final inner = opener.substring(1, opener.length - 1);
    final eq = inner.indexOf('=');
    if (eq < 0) return '[/$inner]';
    final name = inner.substring(0, eq);
    return name == 'align' ? '[/$inner]' : '[/$name]';
  }

  /// Parse a hex color string like "#FF0000" or "FF0000" into a Color.
  static Color? _parseHexColor(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final v = int.tryParse(hex, radix: 16);
    return v == null ? null : Color(v);
  }
}

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
