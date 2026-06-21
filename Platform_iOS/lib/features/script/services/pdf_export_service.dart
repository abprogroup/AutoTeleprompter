import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'markup_export_service.dart';

class PdfExportService {
  PdfExportService._();

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;
  static pw.Font? _italicFont;

  static Future<List<int>> generate(String text, {bool? defaultRtl}) async {
    final regular = await _loadFont(
      cached: _regularFont,
      systemCandidates: const [
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      ],
      assetFallback: 'assets/fonts/google_fonts/Inter-Regular.ttf',
      assign: (font) => _regularFont = font,
    );
    final bold = await _loadFont(
      cached: _boldFont,
      systemCandidates: const [
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      ],
      assetFallback: 'assets/fonts/google_fonts/Inter-Bold.ttf',
      assign: (font) => _boldFont = font,
    );
    final italic = await _loadFont(
      cached: _italicFont,
      systemCandidates: const [
        '/System/Library/Fonts/Supplemental/Arial Italic.ttf',
      ],
      assetFallback: 'assets/fonts/google_fonts/Inter-Italic.ttf',
      assign: (font) => _italicFont = font,
      allowRegularFallback: true,
    );

    final document = pw.Document();
    final paragraphs = MarkupExportService.parse(
      text,
      defaultRtl: defaultRtl,
    );
    final rtlParagraphs = paragraphs.where((paragraph) => paragraph.isRtl);
    final documentDirection = rtlParagraphs.length >= paragraphs.length / 2
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;
    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(36, 42, 36, 42),
          textDirection: documentDirection,
          theme: pw.ThemeData.withFont(
            base: regular,
            bold: bold,
            italic: italic,
            boldItalic: bold,
          ),
        ),
        build: (context) => [
          for (final paragraph in paragraphs)
            _paragraphWidget(paragraph, regular, bold, italic),
        ],
      ),
    );
    return document.save();
  }

  static Future<pw.Font> _loadFont({
    required pw.Font? cached,
    required List<String> systemCandidates,
    required String assetFallback,
    required void Function(pw.Font font) assign,
    bool allowRegularFallback = false,
  }) async {
    if (cached != null) return cached;
    for (final path in systemCandidates) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final font = pw.Font.ttf(ByteData.sublistView(bytes));
        assign(font);
        return font;
      }
    }
    try {
      final data = await rootBundle.load(assetFallback);
      final font = pw.Font.ttf(data.buffer.asByteData());
      assign(font);
      return font;
    } catch (_) {
      if (allowRegularFallback) {
        final regular = _regularFont;
        if (regular != null) {
          assign(regular);
          return regular;
        }
      }
      final font = pw.Font.helvetica();
      assign(font);
      return font;
    }
  }

  static pw.Widget _paragraphWidget(
    ExportParagraph paragraph,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic,
  ) {
    if (paragraph.isEmpty) return pw.SizedBox(height: 12);
    final paragraphBackground = _uniformParagraphBackground(paragraph);
    final richText = pw.RichText(
      textDirection:
          paragraph.isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: _pdfAlign(paragraph),
      text: pw.TextSpan(
        children: [
          for (final directionalRun in MarkupExportService.documentRuns(
            paragraph,
          ))
            _pdfSpan(
              directionalRun.run,
              directionalRun.text,
              isRtl: directionalRun.isRtl,
              regular: regular,
              bold: bold,
              italic: italic,
              includeBackground: paragraphBackground == null,
            ),
        ],
      ),
    );
    return pw.Directionality(
      textDirection:
          paragraph.isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: paragraphBackground == null
            ? richText
            : pw.Align(
                alignment: _pdfAlignment(paragraph),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                  decoration: pw.BoxDecoration(color: paragraphBackground),
                  child: richText,
                ),
              ),
      ),
    );
  }

  static PdfColor? _uniformParagraphBackground(ExportParagraph paragraph) {
    String? background;
    var sawVisibleText = false;
    for (final run in paragraph.runs) {
      if (run.text.trim().isEmpty) continue;
      sawVisibleText = true;
      final color = run.backgroundColor;
      if (color == null) return null;
      background ??= color;
      if (background.toUpperCase() != color.toUpperCase()) return null;
    }
    if (!sawVisibleText || background == null) return null;
    return _pdfColor(background);
  }

  static pw.Alignment _pdfAlignment(ExportParagraph paragraph) {
    if (paragraph.isRtl && !paragraph.hasExplicitAlign) {
      return pw.Alignment.centerRight;
    }
    return switch (paragraph.align) {
      'center' => pw.Alignment.center,
      'right' => pw.Alignment.centerRight,
      _ => pw.Alignment.centerLeft,
    };
  }

  static pw.TextAlign _pdfAlign(ExportParagraph paragraph) {
    if (paragraph.isRtl && !paragraph.hasExplicitAlign) {
      return pw.TextAlign.right;
    }
    return switch (paragraph.align) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      _ => pw.TextAlign.left,
    };
  }

  static pw.InlineSpan _pdfSpan(
    ExportTextRun run,
    String text, {
    required bool isRtl,
    required pw.Font regular,
    required pw.Font bold,
    required pw.Font italic,
    bool includeBackground = true,
  }) {
    final displayText = BidiExportMarks.wrap(text, rtl: isRtl);
    final style = _runStyle(
      run,
      regular,
      bold,
      italic,
      includeBackground: includeBackground,
    );
    return pw.TextSpan(text: displayText, style: style);
  }

  static pw.TextStyle _runStyle(
    ExportTextRun run,
    pw.Font regular,
    pw.Font bold,
    pw.Font italic, {
    bool includeBackground = true,
  }) {
    final isBold = run.isBold;
    final isItalic = run.isItalic;
    return pw.TextStyle(
      font: isBold
          ? bold
          : isItalic
              ? italic
              : regular,
      fontSize: (run.fontSize ?? 18).clamp(8, 96).toDouble(),
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: run.isUnderline
          ? pw.TextDecoration.underline
          : pw.TextDecoration.none,
      color: _pdfColor(run.color, omitWhite: true),
      background:
          includeBackground ? _pdfBackground(run.backgroundColor) : null,
    );
  }

  static pw.BoxDecoration? _pdfBackground(String? hex) {
    final color = _pdfColor(hex);
    return color == null ? null : pw.BoxDecoration(color: color);
  }

  static PdfColor? _pdfColor(String? hex, {bool omitWhite = false}) {
    final clean = hex?.trim().replaceFirst('#', '').toUpperCase();
    if (clean == null || clean.length != 6) return null;
    if (omitWhite && clean == 'FFFFFF') return null;
    final value = int.tryParse(clean, radix: 16);
    if (value == null) return null;
    return PdfColor.fromInt(0xFF000000 | value);
  }
}
