import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/services/docx_service.dart';
import 'package:autoteleprompter/features/script/services/markup_export_service.dart';
import 'package:autoteleprompter/features/script/services/pdf_export_service.dart';
import 'package:autoteleprompter/features/script/services/rtf_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('markup export keeps highlights separate from text colors', () {
    final paragraph = MarkupExportService.parse(
      '[rtl][y]highlight[/y] [yc]yellow text[/yc][/rtl]',
      defaultRtl: true,
    ).single;

    expect(paragraph.isRtl, isTrue);
    expect(paragraph.runs[0].backgroundColor, 'FFD700');
    expect(paragraph.runs[0].color, isNull);
    expect(paragraph.runs[1].text, ' ');
    expect(paragraph.runs[2].color, 'FFD700');
    expect(paragraph.runs[2].backgroundColor, isNull);
  });

  test('plain export strips private markup tags', () {
    final plain = MarkupExportService.toPlainText(
      '[font=Lora]Hello[/font] [bg=#FF0000]world[/bg]',
    );

    expect(plain, 'Hello world');
    expect(plain, isNot(contains('[font=')));
    expect(plain, isNot(contains('[bg=')));
  });

  test('RTF export writes highlight controls without leaking markup', () {
    final bytes = RtfService.generate('[y]Highlight[/y] plain');
    final rtf = utf8.decode(bytes);

    expect(rtf, contains(r'\highlight1'));
    expect(rtf, isNot(contains('[y]')));
    expect(rtf, isNot(contains('[/y]')));
  });

  test('DOCX export preserves RTL paragraphs without leaking markup', () {
    final archive = ZipDecoder().decodeBytes(
      DocxService.generate('[rtl]שלום עולם[/rtl]', defaultRtl: true),
    );
    final document = archive.findFile('word/document.xml');
    expect(document, isNotNull);

    final xml = utf8.decode(document!.content as List<int>);
    expect(xml, contains('<w:bidi/>'));
    expect(xml, contains('<w:rtl/>'));
    expect(xml, isNot(contains('[rtl]')));
  });

  test('PDF export generates a document for Hebrew RTL text on iOS', () async {
    final bytes = await PdfExportService.generate(
      '[rtl]שלום עולם[/rtl]\n**Bold English**',
      defaultRtl: true,
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4).toList()), '%PDF');
  });

  test('PDF export italic fallback points at a bundled italic font', () async {
    final data = await rootBundle.load(PdfExportService.italicAssetFallback);
    expect(data.lengthInBytes, greaterThan(1000));
  });
}
