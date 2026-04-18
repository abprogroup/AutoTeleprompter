import 'package:flutter/material.dart';

class ScriptWord {
  final String raw;
  final String normalized;
  final int index;
  final bool isRtl;
  final bool isNewline;   // paragraph break — renders as full-width empty spacer
  final bool isBold;
  final bool isUnderline;
  final double? fontSize;
  final TextAlign? alignment; // paragraph alignment
  final bool isItalic;
  final bool? isParagraphRtl; // manual direction override
  final Color? highlight;     // background highlight: yellow, red, green
  final Color? textColor;     // text color override: yellow, red, green

  const ScriptWord({
    required this.raw,
    required this.normalized,
    required this.index,
    required this.isRtl,
    this.isNewline = false,
    this.isBold = false,
    this.isUnderline = false,
    this.fontSize,
    this.alignment, // Default to null (fall back to settings)
    this.isItalic = false,
    this.isParagraphRtl, // If null, auto-detect from isRtl
    this.highlight,
    this.textColor,
  });
  
  bool get effectiveRtl => isParagraphRtl ?? isRtl;
}
