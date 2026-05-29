part of 'script_provider.dart';

class ParsedFile {
  final String text;
  final double? fontSize;
  final String? errorMessage;

  ParsedFile(
    this.text, {
    this.fontSize,
    this.errorMessage,
  });

  bool get isError => errorMessage != null;
}

class _DocxRunStyle {
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? color;
  final String? highlightColor;

  const _DocxRunStyle({
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.color,
    this.highlightColor,
  });
}

class _DocxRunSegment {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final String? color;
  final String? highlightColor;

  const _DocxRunSegment(
    this.text, {
    required this.isBold,
    required this.isItalic,
    required this.isUnderline,
    required this.color,
    required this.highlightColor,
  });

  bool sameStyle(_DocxRunSegment other) =>
      isBold == other.isBold &&
      isItalic == other.isItalic &&
      isUnderline == other.isUnderline &&
      color == other.color &&
      highlightColor == other.highlightColor;

  _DocxRunSegment copyWith({required String text}) => _DocxRunSegment(
        text,
        isBold: isBold,
        isItalic: isItalic,
        isUnderline: isUnderline,
        color: color,
        highlightColor: highlightColor,
      );
}

class _RtfRun {
  final String text;
  final bool bold;
  final int cfIndex;
  _RtfRun(this.text, this.bold, this.cfIndex);
}
