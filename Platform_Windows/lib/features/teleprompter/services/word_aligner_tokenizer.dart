part of 'word_aligner.dart';

class _WordAlignerTokenizer {
  /// Parse raw script text into a list of ScriptWords.
  /// Preserves paragraph breaks as isNewline=true entries.
  static List<ScriptWord> tokenize(String text) {
    final words = <ScriptWord>[];
    int index = 0;

    final lines = text.split('\n');

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
        final lineSkipsSpeech = _isProductionCueLine(line);
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
            final skipSpeech = lineSkipsSpeech ||
                _isLeadingSpeakerLabel(cleanPart, visiblePartIndex);
            final normalized =
                skipSpeech ? '' : cleanPart.normalizeForMatching();
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

  static List<_Span> _parseMarkup(String line) {
    return _parseMarkupRecursive(line, const _Span(''));
  }

  // Recursive markup parser — supports nested tags (e.g. **[rc]word[/rc]**)
  static List<_Span> _parseMarkupRecursive(String text, _Span base) {
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
      r'|\[size=(\d+(?:\.\d+)?)\](.*?)\[\/size\]'
      r'|\[(center|left|right)\](.*?)\[\/\21\]'
      r'|\[align=(center|left|right)\](.*?)\[\/align=\23\]'
      r'|\[i\](.*?)\[\/i\]'
      r'|\[(rtl|ltr)\](.*?)\[\/\26\]'
      r'|\[color=([^\]]+)\](.*?)\[\/color\]'
      r'|\[bg=([^\]]+)\](.*?)\[\/bg\]'
      r'|\[font=([^\]]+)\](.*?)\[\/font\]',
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
        spans.addAll(_parseMarkupRecursive(
            m.group(2)!,
            base.copyWith(
                text: '', highlight: Colors.yellow.withValues(alpha: 0.6))));
      } else if (m.group(3) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(3)!,
            base.copyWith(
                text: '', highlight: Colors.red.withValues(alpha: 0.55))));
      } else if (m.group(4) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(4)!,
            base.copyWith(
                text: '', highlight: Colors.green.withValues(alpha: 0.55))));
      } else if (m.group(5) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(5)!,
            base.copyWith(
                text: '', highlight: Colors.blue.withValues(alpha: 0.45))));
      } else if (m.group(6) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(6)!,
            base.copyWith(
                text: '', highlight: Colors.orange.withValues(alpha: 0.50))));
      } else if (m.group(7) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(7)!,
            base.copyWith(
                text: '', highlight: Colors.purple.withValues(alpha: 0.45))));
      } else if (m.group(8) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(8)!,
            base.copyWith(
                text: '', highlight: Colors.cyan.withValues(alpha: 0.45))));
      } else if (m.group(9) != null) {
        spans.addAll(_parseMarkupRecursive(
            m.group(9)!,
            base.copyWith(
                text: '', highlight: Colors.pink.withValues(alpha: 0.45))));
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
        spans.addAll(_parseMarkupRecursive(m.group(27)!,
            base.copyWith(text: '', isParagraphRtl: dir == 'rtl')));
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
      } else if (m.group(32) != null && m.group(33) != null) {
        // [font=Family] is visual metadata only for the presenter/STT word
        // list. Consume the tag so family names with spaces never become
        // spoken words or visible presenter text.
        spans.addAll(_parseMarkupRecursive(m.group(33)!, base));
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
