import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  late Directory fixtures;
  setUp(() async {
    fixtures = await Directory.systemTemp.createTemp('atp_docx_styles_');
  });
  tearDown(() async {
    await fixtures.delete(recursive: true);
  });

  Future<ParsedFile> parse(String body, {String styles = ''}) async {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add(
      'word/document.xml',
      '<w:document xmlns:w="$_ns"><w:body>$body</w:body></w:document>',
    );
    add('word/styles.xml', '<w:styles xmlns:w="$_ns">$styles</w:styles>');
    final source = File('${fixtures.path}/sample.docx');
    await source.writeAsBytes(ZipEncoder().encode(archive)!);
    final result = await ScriptNotifier().parseFile(source);
    expect(result.isError, isFalse, reason: result.errorMessage);
    return result;
  }

  test(
    'document defaults apply to unformatted text and retain uniform size',
    () async {
      final result = await parse(
        '<w:p><w:r><w:t>Hello</w:t></w:r></w:p>',
        styles: '''
      <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>''',
      );
      expect(result.fontSize, 11);
      expect(result.text, contains('[font=Arial][size=11]Hello[/size][/font]'));
    },
  );

  test('paragraph-mark underline does not leak into visible text', () async {
    final result = await parse(
      '<w:p><w:pPr><w:rPr><w:u/></w:rPr></w:pPr><w:r><w:t>Plain</w:t></w:r><w:r><w:rPr><w:u/></w:rPr><w:t> Marked</w:t></w:r></w:p>',
    );
    final words = WordAligner.tokenize(result.text);
    expect(words.map((w) => w.isUnderline), [false, true]);
  });

  test('highlight overrides shading and none reveals shading', () async {
    final result = await parse(
      '''<w:p>
      <w:r><w:rPr><w:highlight w:val="yellow"/><w:shd w:fill="0000FF"/></w:rPr><w:t>One </w:t></w:r>
      <w:r><w:rPr><w:highlight w:val="none"/><w:shd w:fill="0000FF"/></w:rPr><w:t>Two</w:t></w:r></w:p>''',
    );
    expect(WordAligner.tokenize(result.text).map((w) => w.highlight), [
      const Color(0xFFFFFF00),
      const Color(0xFF0000FF),
    ]);
  });

  test(
    'named paragraph and character styles cascade before direct overrides',
    () async {
      final result = await parse(
        '''<w:p><w:pPr><w:pStyle w:val="Heading"/></w:pPr>
      <w:r><w:rPr><w:rStyle w:val="Emphasis"/><w:u w:val="none"/></w:rPr><w:t>Title</w:t></w:r></w:p>''',
        styles: '''
      <w:style w:type="paragraph" w:styleId="Normal" w:default="1"><w:rPr><w:sz w:val="22"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading"><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:u/><w:sz w:val="40"/></w:rPr></w:style>
      <w:style w:type="character" w:styleId="Emphasis"><w:rPr><w:i/><w:color w:val="FF0000"/></w:rPr></w:style>''',
      );
      final word = WordAligner.tokenize(result.text).single;
      expect(word.isBold, isTrue);
      expect(word.isItalic, isTrue);
      expect(word.isUnderline, isFalse);
      expect(word.fontSize, 20);
      expect(word.alignment, TextAlign.center);
      expect(word.textColor, const Color(0xFFFF0000));
    },
  );

  test(
    'default paragraph style and explicit off do not affect adjacent runs',
    () async {
      final result = await parse(
        '''<w:p>
      <w:r><w:rPr><w:b w:val="false"/><w:highlight w:val="none"/></w:rPr><w:t>Plain </w:t></w:r>
      <w:r><w:t>Styled</w:t></w:r></w:p>''',
        styles: '''
      <w:style w:type="paragraph" w:styleId="Normal" w:default="1"><w:rPr><w:b/><w:highlight w:val="yellow"/></w:rPr></w:style>''',
      );
      final words = WordAligner.tokenize(result.text);
      expect(words.map((w) => w.isBold), [false, true]);
      expect(words.map((w) => w.highlight), [null, const Color(0xFFFFFF00)]);
    },
  );

  test(
    'mixed sizes are preserved without guessing global size from first run',
    () async {
      final result = await parse(
        '''<w:p><w:r><w:rPr><w:sz w:val="60"/></w:rPr><w:t>Title </w:t></w:r>
      <w:r><w:t>Body</w:t></w:r></w:p>''',
        styles: '''
      <w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>''',
      );
      expect(result.fontSize, isNull);
      expect(WordAligner.tokenize(result.text).map((w) => w.fontSize), [
        30,
        11,
      ]);
    },
  );

  test(
    'Hebrew complex-script formatting and false bidi are preserved',
    () async {
      final result = await parse(
        '''<w:p><w:pPr><w:bidi w:val="0"/></w:pPr>
      <w:r><w:rPr><w:bCs/><w:iCs/><w:sz w:val="24"/><w:szCs w:val="36"/>
      <w:rFonts w:ascii="Arial" w:cs="David"/></w:rPr><w:t>שלום</w:t></w:r></w:p>''',
      );
      final word = WordAligner.tokenize(result.text).single;
      expect(word.isBold, isTrue);
      expect(word.isItalic, isTrue);
      expect(word.fontSize, 18);
      expect(result.text, contains('[font=David]'));
      expect(word.fontFamily, 'David');
      expect(word.isParagraphRtl, isFalse);
    },
  );

  test('style toggles and cycles are bounded', () async {
    final result = await parse(
      '<w:p><w:pPr><w:pStyle w:val="Child"/></w:pPr><w:r><w:t>Hello</w:t></w:r></w:p>',
      styles: '''
      <w:style w:type="paragraph" w:styleId="Parent"><w:basedOn w:val="Child"/><w:rPr><w:b/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Child"><w:basedOn w:val="Parent"/><w:rPr><w:b/><w:i/></w:rPr></w:style>''',
    );
    final word = WordAligner.tokenize(result.text).single;
    expect(word.isBold, isFalse);
    expect(word.isItalic, isTrue);
  });

  test(
    'font-family scopes reach presenter tokens without changing speech text',
    () {
      final words = WordAligner.tokenize(
        '[font=Arial]One [font=David]שלום[/font] two\nthree[/font] plain',
      );
      final visible = words.where((w) => !w.isNewline).toList();
      expect(visible.map((w) => w.fontFamily), [
        'Arial',
        'David',
        'Arial',
        'Arial',
        null,
      ]);
      expect(visible.map((w) => w.normalized), [
        'one',
        'שלום',
        'two',
        'three',
        'plain',
      ]);
    },
  );
}
