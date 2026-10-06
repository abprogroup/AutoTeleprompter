import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  Future<ParsedFile> parse(
    String body, {
    String styles = '',
    String numbering = '',
  }) async {
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
    add(
      'word/numbering.xml',
      '<w:numbering xmlns:w="$_ns">$numbering</w:numbering>',
    );
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

  const numberReference =
      '<w:numPr><w:ilvl w:val="0"/>'
      '<w:numId w:val="1"/></w:numPr>';
  const defaults =
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Arial" w:cs="Arial"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/>'
      '</w:rPr></w:rPrDefault></w:docDefaults>';
  String numberDefinition({String properties = '', String override = ''}) =>
      '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0">'
      '<w:start w:val="1"/><w:numFmt w:val="decimal"/>'
      '<w:lvlText w:val="%1."/><w:rPr>$properties</w:rPr>'
      '</w:lvl></w:abstractNum><w:num w:numId="1">'
      '<w:abstractNumId w:val="0"/>$override</w:num>';

  test(
    'generated list labels retain document font and size beside Hebrew',
    () async {
      final result = await parse(
        '<w:p><w:pPr>$numberReference<w:bidi/></w:pPr>'
        '<w:r><w:rPr><w:highlight w:val="magenta"/><w:u/></w:rPr>'
        '<w:t>כותרת</w:t></w:r></w:p>',
        styles: defaults,
        numbering: numberDefinition(properties: '<w:u w:val="none"/>'),
      );
      final words = WordAligner.tokenize(result.text);
      expect(words.map((w) => w.raw), ['1.', 'כותרת']);
      expect(words.map((w) => w.fontSize), [11, 11]);
      expect(words.map((w) => w.fontFamily), ['Arial', 'Arial']);
      expect(words.map((w) => w.isUnderline), [false, true]);
      expect(words.map((w) => w.highlight), [null, const Color(0xFFFF00FF)]);
      expect(result.fontSize, 11);
    },
  );

  test(
    'list font size inherits the paragraph style, not first run formatting',
    () async {
      final result = await parse(
        '<w:p><w:pPr>$numberReference<w:pStyle w:val="Heading"/></w:pPr>'
        '<w:r><w:rPr><w:sz w:val="60"/></w:rPr><w:t>Title</w:t></w:r></w:p>',
        styles:
            '$defaults<w:style w:type="paragraph" w:styleId="Heading">'
            '<w:rPr><w:sz w:val="28"/></w:rPr></w:style>',
        numbering: numberDefinition(),
      );
      expect(WordAligner.tokenize(result.text).map((w) => w.fontSize), [
        14,
        30,
      ]);
      expect(result.fontSize, isNull);
    },
  );

  test(
    'numbering font overrides are scoped to labels and affect uniform size',
    () async {
      final result = await parse(
        '<w:p><w:pPr>$numberReference</w:pPr>'
        '<w:r><w:t>Body</w:t></w:r></w:p>',
        styles: defaults,
        numbering: numberDefinition(
          properties: '<w:sz w:val="32"/><w:rFonts w:ascii="Courier New"/>',
        ),
      );
      final words = WordAligner.tokenize(result.text);
      expect(words.map((w) => w.fontSize), [16, 11]);
      expect(words.map((w) => w.fontFamily), ['Courier New', 'Arial']);
      expect(result.fontSize, isNull);
    },
  );

  test('paragraph mark typography applies to label only', () async {
    final result = await parse(
      '<w:p><w:pPr>$numberReference<w:rPr>'
      '<w:sz w:val="36"/><w:rFonts w:ascii="David"/>'
      '</w:rPr></w:pPr><w:r><w:t>Body</w:t></w:r></w:p>',
      styles: defaults,
      numbering: numberDefinition(),
    );
    final words = WordAligner.tokenize(result.text);
    expect(words.map((w) => w.fontSize), [18, 11]);
    expect(words.map((w) => w.fontFamily), ['David', 'Arial']);
  });

  test(
    'explicit complex-script numbering properties apply to digit labels',
    () async {
      final result = await parse(
        '<w:p><w:pPr>$numberReference<w:bidi/></w:pPr>'
        '<w:r><w:t>כותרת</w:t></w:r></w:p>',
        styles: defaults,
        numbering: numberDefinition(
          properties:
              '<w:rtl/><w:sz w:val="24"/><w:szCs w:val="36"/>'
              '<w:rFonts w:ascii="Arial" w:cs="David"/>',
        ),
      );
      final words = WordAligner.tokenize(result.text);
      expect(words.map((w) => w.fontSize), [18, 11]);
      expect(words.map((w) => w.fontFamily), ['David', 'Arial']);
    },
  );

  test(
    'start-only list override preserves level typography and counter',
    () async {
      final result = await parse(
        '<w:p><w:pPr>$numberReference</w:pPr>'
        '<w:r><w:t>First</w:t></w:r></w:p>'
        '<w:p><w:pPr>$numberReference</w:pPr>'
        '<w:r><w:t>Second</w:t></w:r></w:p>',
        styles: defaults,
        numbering: numberDefinition(
          properties: '<w:sz w:val="28"/>',
          override:
              '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="4"/>'
              '</w:lvlOverride>',
        ),
      );
      final words =
          WordAligner.tokenize(result.text).where((w) => !w.isNewline).toList();
      expect(words.map((w) => w.raw), ['4.', 'First', '5.', 'Second']);
      expect(words.map((w) => w.fontSize), [14, 11, 14, 11]);
    },
  );

  test('list-level replacement uses its own typography', () async {
    final result = await parse(
      '<w:p><w:pPr>$numberReference</w:pPr><w:r><w:t>Body</w:t></w:r></w:p>',
      styles: defaults,
      numbering: numberDefinition(
        properties: '<w:sz w:val="32"/>',
        override:
            '<w:lvlOverride w:ilvl="0"><w:lvl w:ilvl="0">'
            '<w:start w:val="2"/><w:numFmt w:val="upperRoman"/>'
            '<w:lvlText w:val="%1)"/><w:rPr><w:sz w:val="40"/>'
            '</w:rPr></w:lvl></w:lvlOverride>',
      ),
    );
    final words = WordAligner.tokenize(result.text);
    expect(words.map((w) => w.raw), ['II)', 'Body']);
    expect(words.map((w) => w.fontSize), [20, 11]);
  });

  test('missing document typography does not invent label metadata', () async {
    final result = await parse(
      '<w:p><w:pPr>$numberReference</w:pPr>'
      '<w:r><w:rPr><w:sz w:val="60"/></w:rPr><w:t>Title</w:t></w:r></w:p>',
      numbering: numberDefinition(),
    );
    final words = WordAligner.tokenize(result.text);
    expect(words.map((w) => w.fontSize), [null, 30]);
    expect(result.fontSize, isNull);
  });

  testWidgets('editor list size is independent of saved app font size', (
    tester,
  ) async {
    final result =
        (await tester.runAsync(
          () => parse(
            '<w:p><w:pPr>$numberReference<w:bidi/></w:pPr>'
            '<w:r><w:t>כותרת</w:t></w:r></w:p>',
            styles: defaults,
            numbering: numberDefinition(),
          ),
        ))!;
    final capture =
        Platform.environment['ATP_CAPTURE_NUMBER_SIZE_PROOF'] == '1';
    if (capture) {
      await tester.runAsync(() async {
        final loader = FontLoader('Arial')..addFont(
          File(
            'C:/Windows/Fonts/arial.ttf',
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
        await loader.load();
      });
    }
    final controllers = [
      MarkupController(text: result.text),
      MarkupController(text: result.text),
    ];
    final proofKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: proofKey,
              child: Container(
                width: 520,
                color: Colors.white,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'DOCX list typography - editor renderer',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.black,
                        fontFamily: 'Arial',
                      ),
                    ),
                    for (var i = 0; i < controllers.length; i++) ...[
                      const SizedBox(height: 20),
                      Text(
                        'App default: ${i == 0 ? 24 : 64} | document: 11',
                        style: const TextStyle(
                          color: Colors.purple,
                          fontFamily: 'Arial',
                        ),
                      ),
                      TextField(
                        controller: controllers[i],
                        readOnly: true,
                        showCursor: false,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: i == 0 ? 24 : 64,
                          fontFamily: 'Arial',
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final labelHeights = <double>[];
    for (var i = 0; i < controllers.length; i++) {
      final context = tester.element(find.byType(EditableText).at(i));
      final span = controllers[i].buildTextSpan(
        context: context,
        style: TextStyle(fontSize: i == 0 ? 24 : 64),
        withComposing: false,
      );
      final visible = <TextSpan>[];
      span.visitChildren((span) {
        if (span is TextSpan &&
            (span.text?.trim() == '1.' || span.text == 'כותרת')) {
          visible.add(span);
        }
        return true;
      });
      expect(visible.map((s) => s.style?.fontSize), [11, 11]);
      expect(visible.map((s) => s.style?.fontFamily), ['Arial', 'Arial']);
      final editable =
          tester
              .state<EditableTextState>(find.byType(EditableText).at(i))
              .renderEditable;
      final start = result.text.indexOf('1.');
      final boxes = editable.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + 1),
      );
      expect(boxes, isNotEmpty);
      labelHeights.add(boxes.first.toRect().height);
      expect(controllers[i].customPaintSelection, isNull);
    }
    expect(labelHeights.first, greaterThan(0));
    expect(labelHeights.last, closeTo(labelHeights.first, 0.01));
    if (capture) {
      final boundary =
          proofKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final rendered = await boundary.toImage(pixelRatio: 3);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        final proof = File(
          'test/deep_analysis/docx_number_size/final_proof.png',
        );
        await proof.parent.create(recursive: true);
        await proof.writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      controller.dispose();
    }
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
