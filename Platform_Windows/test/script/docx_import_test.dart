import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  test('DOCX import preserves underline, breaks, and empty paragraphs',
      () async {
    final dir = await Directory.systemTemp.createTemp('docx_import_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/styled.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:pPr><w:jc w:val="right"/></w:pPr>
  <w:r><w:rPr><w:b/><w:u w:val="single"/></w:rPr><w:t>bold underline</w:t></w:r>
</w:p>
<w:p/>
<w:p>
  <w:r><w:t>first line</w:t><w:br/><w:t>second line</w:t></w:r>
</w:p>
<w:p>
  <w:r><w:rPr><w:i/></w:rPr><w:t>italic</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(text, contains('[align=right]'));
    expect(text, contains('**[u]bold underline[/u]**'));
    expect(text, contains('\n\nfirst line\nsecond line'));
    expect(text, contains('[i]italic[/i]'));
  });

  test('DOCX import preserves meaningful colors and row highlights safely',
      () async {
    final dir = await Directory.systemTemp.createTemp('docx_color_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/colors.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:r><w:rPr><w:color w:val="252525"/></w:rPr><w:t>default dark text</w:t></w:r>
</w:p>
<w:p>
  <w:r><w:rPr><w:color w:val="FF0000"/></w:rPr><w:t>red text</w:t></w:r>
</w:p>
<w:p>
  <w:r><w:rPr><w:shd w:fill="FCE5CD"/></w:rPr><w:t>shaded row</w:t></w:r>
</w:p>
<w:p>
  <w:r><w:rPr><w:highlight w:val="yellow"/></w:rPr><w:t>highlight row</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(text, contains('default dark text'));
    expect(text, isNot(contains('[color=#252525]default dark text[/color]')));
    expect(text, contains('[color=#FF0000]red text[/color]'));
    expect(text, contains('[bg=#FCE5CD]shaded row[/bg]'));
    expect(text, contains('[bg=#FFFF00]highlight row[/bg]'));
  });

  test('DOCX import coalesces adjacent runs with the same style', () async {
    final dir = await Directory.systemTemp.createTemp('docx_merge_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/merged.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:r><w:rPr><w:shd w:fill="FCE5CD"/><w:u w:val="single"/></w:rPr><w:t>first </w:t></w:r>
  <w:r><w:rPr><w:shd w:fill="FCE5CD"/><w:u w:val="single"/></w:rPr><w:t>second</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(text, contains('[u][bg=#FCE5CD]first second[/bg][/u]'));
    expect('[bg=#FCE5CD]'.allMatches(text), hasLength(1));
  });

  test('DOCX import inherits paragraph run defaults', () async {
    final dir = await Directory.systemTemp.createTemp('docx_ppr_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/paragraph_defaults.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:pPr>
    <w:bidi/>
    <w:rPr><w:highlight w:val="green"/><w:u w:val="single"/></w:rPr>
  </w:pPr>
  <w:r><w:rPr><w:rtl/></w:rPr><w:t>paragraph default style</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(
      text,
      contains('[align=right][u][bg=#00FF00]paragraph default style[/bg][/u]'),
    );
  });

  test('DOCX import attaches standalone RTL brackets to text runs', () async {
    final dir = await Directory.systemTemp.createTemp('docx_bracket_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/brackets.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:pPr><w:bidi/></w:pPr>
  <w:r><w:rPr><w:rtl/></w:rPr><w:t>[</w:t></w:r>
  <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t>\u05d4\u05e4\u05e7\u05e1 \u05e9\u05dc \u05d4\u05de\u05d8\u05d1\u05d7]</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(
      text,
      contains(
        '[align=right]**[\u05d4\u05e4\u05e7\u05e1 \u05e9\u05dc \u05d4\u05de\u05d8\u05d1\u05d7]**',
      ),
    );
    expect(text, isNot(contains('[align=right][**')));
  });
}

List<int> _docxBytes(String bodyXml) {
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''');
  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''');
  add('word/document.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $bodyXml
  </w:body>
</w:document>
''');

  return ZipEncoder().encode(archive)!;
}
