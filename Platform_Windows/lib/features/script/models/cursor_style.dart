import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// v3.35.9: Hardened Style Synchronization Bridge
final cursorStyleProvider = StateProvider<CursorStyle>((ref) => CursorStyle());

class CursorStyle {
  final bool isBold, isItalic, isUnderline;
  final int fontSize;
  final String fontFamily, textAlign;
  final Color? textColor, highlightColor;
  
  CursorStyle({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.fontSize = 40,
    this.fontFamily = 'Inter',
    this.textAlign = 'left',
    this.textColor,
    this.highlightColor,
  });

  CursorStyle copyWith({
    bool? isBold, bool? isItalic, bool? isUnderline,
    int? fontSize, String? fontFamily, String? textAlign,
    Color? textColor, Color? highlightColor
  }) {
    return CursorStyle(
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      textColor: textColor ?? this.textColor,
      highlightColor: highlightColor ?? this.highlightColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CursorStyle &&
          runtimeType == other.runtimeType &&
          isBold == other.isBold &&
          isItalic == other.isItalic &&
          isUnderline == other.isUnderline &&
          fontSize == other.fontSize &&
          fontFamily == other.fontFamily &&
          textAlign == other.textAlign &&
          textColor == other.textColor &&
          highlightColor == other.highlightColor;

  @override
  int get hashCode =>
      isBold.hashCode ^ isItalic.hashCode ^ isUnderline.hashCode ^
      fontSize.hashCode ^ fontFamily.hashCode ^ textAlign.hashCode ^
      textColor.hashCode ^ highlightColor.hashCode;
}
