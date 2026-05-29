import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/feedback/services/lightweight_diagnostics.dart';
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

  test('DOCX import preserves RTL bracket dash paragraph as source truth',
      () async {
    final dir = await Directory.systemTemp.createTemp('docx_rtl_dash_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/rtl_dash.docx');
    await file.writeAsBytes(_docxBytes('''
<w:p>
  <w:pPr><w:bidi/></w:pPr>
  <w:r><w:rPr><w:rtl/></w:rPr><w:t>\u05d0\u05e0\u05d9 \u05d1\u05db\u05dc\u05dc \u05de\u05e8\u05d2\u05d9\u05e9 \u05e9\u05d4\u05db\u05d1\u05d5\u05d3 \u05e9\u05dc\u05d4\u05dd \u05d0\u05dc\u05d9 \u05db\u05d0\u05d1\u05d0 \u05d9\u05e8\u05d3 \u05d1\u05de\u05dc\u05d7\u05de\u05d4.</w:t></w:r>
  <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t>[\u05d0\u05e0\u05d9 \u05dc\u05d0 \u05d9\u05d5\u05e9\u05d1 \u05d1\u05e8\u05d0\u05e9 \u05d4\u05e9\u05d5\u05dc\u05d7\u05df?]- \u05d4\u05d9\u05dc\u05d3\u05d9\u05dd \u05d4\u05d0\u05dc\u05d4 \u05db\u05d1\u05e8 \u05e9\u05e0\u05d9\u05dd \u05dc\u05d0 \u05dc\u05d5\u05de\u05d3\u05d9\u05dd.</w:t></w:r>
  <w:r><w:rPr><w:b/><w:rtl/></w:rPr><w:t>[\u05de\u05e4\u05d7\u05d3 \u05e9\u05d4\u05dd \u05d9\u05e6\u05d0\u05d5 \u05dc\u05d9 \u05d7\u05d1\u05e8\u05d9 \u05db\u05e0\u05e1\u05ea]</w:t></w:r>
</w:p>
'''));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(text, contains('[align=right]'));
    expect(
      text,
      contains(
        '[\u05d0\u05e0\u05d9 \u05dc\u05d0 \u05d9\u05d5\u05e9\u05d1 \u05d1\u05e8\u05d0\u05e9 \u05d4\u05e9\u05d5\u05dc\u05d7\u05df?]- \u05d4\u05d9\u05dc\u05d3\u05d9\u05dd',
      ),
    );
    expect(
      text,
      contains(
        '[\u05de\u05e4\u05d7\u05d3 \u05e9\u05d4\u05dd \u05d9\u05e6\u05d0\u05d5 \u05dc\u05d9 \u05d7\u05d1\u05e8\u05d9 \u05db\u05e0\u05e1\u05ea]',
      ),
    );
    expect(text,
        isNot(contains('\u05dc\u05d5\u05de\u05d3\u05d9\u05dd.\u05dc\u05d0')));
  });

  test('DOCX import rejects archives with too many entries safely', () async {
    final dir = await Directory.systemTemp.createTemp('docx_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final archive = Archive();
    for (var i = 0; i < 2001; i++) {
      archive.addFile(ArchiveFile('junk/$i.xml', 2, utf8.encode('<x/>')));
    }
    final file = File('${dir.path}/too_many_entries.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('too many internal files'));
  });

  test('plain import rejects oversized text safely', () async {
    LightweightDiagnostics.instance.clear();
    final dir = await Directory.systemTemp.createTemp('plain_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/too_big.txt');
    final sink = file.openWrite();
    final chunk = List<int>.filled(1024 * 1024, 0x41);
    try {
      for (var i = 0; i < 26; i++) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('too large'));
    expect(text, contains('25MB'));
    final diagnostics = LightweightDiagnostics.instance.snapshot();
    final events = diagnostics['events'] as List<dynamic>;
    expect(
      events.any((event) =>
          event is Map &&
          event['type'] == 'import' &&
          event['message'] == 'file import failed' &&
          (event['data'] as Map?)?['safetyLimit'] == true),
      isTrue,
    );
  });

  test('importFile does not load parser error text as a script', () async {
    final dir = await Directory.systemTemp.createTemp('plain_import_error_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/too_big.txt');
    final sink = file.openWrite();
    final chunk = List<int>.filled(1024 * 1024, 0x41);
    try {
      for (var i = 0; i < 26; i++) {
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(scriptProvider.notifier).importFile(file);

    expect(container.read(scriptProvider), isNull);
  });

  test('RTF import rejects oversized text safely', () async {
    final dir = await Directory.systemTemp.createTemp('rtf_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final file = File('${dir.path}/too_big.rtf');
    final sink = file.openWrite();
    try {
      sink.add(utf8.encode('{\\rtf1 '));
      final chunk = List<int>.filled(1024 * 1024, 0x41);
      for (var i = 0; i < 26; i++) {
        sink.add(chunk);
      }
      sink.add(utf8.encode('}'));
    } finally {
      await sink.close();
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('too large'));
    expect(text, contains('25MB'));
  });

  test('DOCX import rejects oversized internal XML safely', () async {
    final dir = await Directory.systemTemp.createTemp('docx_xml_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final archive = Archive();
    final xml = List<int>.filled(31 * 1024 * 1024, 0x20);
    archive.addFile(ArchiveFile('word/document.xml', xml.length, xml));
    final file = File('${dir.path}/too_big_xml.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('internal file'));
    expect(text, contains('too large'));
  });

  test('PAGES import rejects archives with too many entries safely', () async {
    final dir = await Directory.systemTemp.createTemp('pages_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final archive = Archive();
    for (var i = 0; i < 2001; i++) {
      archive.addFile(ArchiveFile('Data/$i.xml', 2, utf8.encode('<x/>')));
    }
    final file = File('${dir.path}/too_many_entries.pages');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('too many internal files'));
  });

  test('PAGES import rejects oversized internal XML safely', () async {
    final dir = await Directory.systemTemp.createTemp('pages_xml_safety_test_');
    addTearDown(() => dir.delete(recursive: true));

    final archive = Archive();
    final xml = List<int>.filled(31 * 1024 * 1024, 0x20);
    archive.addFile(ArchiveFile('index.xml', xml.length, xml));
    final file = File('${dir.path}/too_big_xml.pages');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final dynamic parsed =
        await container.read(scriptProvider.notifier).parseFile(file);
    final text = parsed.text as String;

    expect(parsed.isError, isTrue);
    expect(text, contains('internal file'));
    expect(text, contains('too large'));
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
