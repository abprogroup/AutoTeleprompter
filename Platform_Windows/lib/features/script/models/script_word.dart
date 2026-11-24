import 'package:flutter/material.dart';

/// A styled sub-word text run preserved when a single word contains mid-word
/// formatting (for example, colored Hebrew nikud/diacritics or partial bold).
class ScriptWordRun {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final double? fontSize;
  final String? fontFamily;
  final Color? textColor;
  final Color? highlight;

  const ScriptWordRun({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.fontSize,
    this.fontFamily,
    this.textColor,
    this.highlight,
  });

  bool hasSameStyle(ScriptWordRun other) =>
      isBold == other.isBold &&
      isItalic == other.isItalic &&
      isUnderline == other.isUnderline &&
      fontSize == other.fontSize &&
      fontFamily == other.fontFamily &&
      textColor == other.textColor &&
      highlight == other.highlight;

  ScriptWordRun copyWith({String? text}) => ScriptWordRun(
    text: text ?? this.text,
    isBold: isBold,
    isItalic: isItalic,
    isUnderline: isUnderline,
    fontSize: fontSize,
    fontFamily: fontFamily,
    textColor: textColor,
    highlight: highlight,
  );
}

class ScriptWord {
  final String raw;
  final String normalized;
  final int index;
  final bool isRtl;
  final bool isNewline; // paragraph break — renders as full-width empty spacer
  final bool isBold;
  final bool isUnderline;
  final double? fontSize;
  final String? fontFamily;
  final TextAlign? alignment; // paragraph alignment
  final bool isItalic;
  final bool? isParagraphRtl; // manual direction override
  final Color? highlight; // background highlight: yellow, red, green
  final Color? textColor; // text color override: yellow, red, green
  final bool isOptionalCue; // stage/camera cue: speakable, but skippable
  final List<ScriptWordRun> runs; // non-empty only for multi-styled words

  const ScriptWord({
    required this.raw,
    required this.normalized,
    required this.index,
    required this.isRtl,
    this.isNewline = false,
    this.isBold = false,
    this.isUnderline = false,
    this.fontSize,
    this.fontFamily,
    this.alignment, // Default to null (fall back to settings)
    this.isItalic = false,
    this.isParagraphRtl, // If null, auto-detect from isRtl
    this.highlight,
    this.textColor,
    this.isOptionalCue = false,
    this.runs = const [],
  });

  bool get effectiveRtl => isParagraphRtl ?? isRtl;
}
