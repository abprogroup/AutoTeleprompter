import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/services/docx_service.dart';
import 'package:autoteleprompter/features/script/services/editor_inline_style_operation.dart';
import 'package:autoteleprompter/features/script/services/odt_service.dart';
import 'package:autoteleprompter/features/script/services/rtf_service.dart';
import 'package:autoteleprompter/features/settings/services/local_backup_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:autoteleprompter/platform/file_import/platform_file_import.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _wNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _mcNs = 'http://schemas.openxmlformats.org/markup-compatibility/2006';

void main() {
  group('Stage 1B — Tokenizer word-cluster & punctuation preservation', () {
    test('keeps punctuation right outside styled span instead of deleting it',
        () {
      final words = WordAligner.tokenize('[bg=#FFFF00]Hello[/bg]!');
      expect(words, hasLength(1));
      expect(words.single.raw, 'Hello!');
      expect(words.single.normalized, 'hello');
      expect(words.single.highlight, const Color(0xFFFFFF00));
    });

    test('does not split single words broken by intra-word markup tags', () {
      final words = WordAligner.tokenize(
        '**un**known [size=20]ש[/size][size=20]לום[/size]',
      );
      expect(words.map((w) => w.raw), ['unknown', 'שלום']);
      expect(words.map((w) => w.normalized), ['unknown', 'שלום']);
      expect(words.first.isBold, isTrue);
      expect(words.last.fontSize, 20);
    });

    test('merges spaced closing punctuation across span boundaries', () {
      final words = WordAligner.tokenize('[bg=#FF00FF]שלום[/bg] !');
      expect(words, hasLength(1));
      expect(words.single.raw, 'שלום!');
      expect(words.single.normalized, 'שלום');
      expect(words.single.highlight, const Color(0xFFFF00FF));
    });
  });

  group('Stage 1B — Exporters preserve script defaultFontSize (no 18pt drop)',
      () {
    test('DOCX, RTF, ODT, and LocalBackupService honor 24pt on mixed lines',
        () {
      const mixedLine = '[size=32]Heading[/size] Body';

      final docxBytes = DocxService.generate(mixedLine, defaultFontSize: 24.0);
      final docxArchive = ZipDecoder().decodeBytes(docxBytes);
      final docXml = utf8.decode(
        docxArchive.findFile('word/document.xml')!.content as List<int>,
      );
      expect(docXml, contains('<w:sz w:val="64"/>'));
      expect(docXml, contains('<w:sz w:val="48"/>'));
      expect(docXml, isNot(contains('<w:sz w:val="36"/>')));

      final rtfText = utf8.decode(
        RtfService.generate(mixedLine, defaultFontSize: 24.0),
      );
      expect(rtfText, contains(r'\fs64'));
      expect(rtfText, contains(r'\fs48'));
      expect(rtfText, isNot(contains(r'\fs36')));

      final odtBytes = OdtService.generate(mixedLine, defaultFontSize: 24.0);
      final odtArchive = ZipDecoder().decodeBytes(odtBytes);
      final contentXml = utf8.decode(
        odtArchive.findFile('content.xml')!.content as List<int>,
      );
      expect(contentXml, contains('fo:font-size="32.0pt"'));
      expect(contentXml, contains('fo:font-size="24.0pt"'));
      expect(contentXml, isNot(contains('fo:font-size="18.0pt"')));

      final backup = LocalBackupService.buildScriptExport(
        title: 'Mixed.docx',
        text: mixedLine,
        sourceType: 'DOCX',
        preferredExtension: 'docx',
        fontSize: 24.0,
      );
      final backupArchive = ZipDecoder().decodeBytes(backup.bytes);
      final backupDocXml = utf8.decode(
        backupArchive.findFile('word/document.xml')!.content as List<int>,
      );
      expect(backupDocXml, contains('<w:sz w:val="64"/>'));
      expect(backupDocXml, contains('<w:sz w:val="48"/>'));
    });
  });

  group('Stage 1B — DOCX & RTF parser accuracy + import guard', () {
    late Directory fixtures;

    setUp(() async {
      fixtures = await Directory.systemTemp.createTemp('atp_stage1b_');
    });

    tearDown(() async {
      await fixtures.delete(recursive: true);
    });

    test('DOCX skips mc:Fallback duplicates and nested w:p text-box double-read',
        () async {
      final archive = Archive();
      const docXml = '<w:document xmlns:w="$_wNs" xmlns:mc="$_mcNs"><w:body>'
          '<w:p>'
          '<w:r><w:t>Outer</w:t></w:r>'
          '<w:r><w:drawing><mc:AlternateContent>'
          '<mc:Choice><w:txbxContent><w:p><w:r><w:t>BoxText</w:t></w:r></w:p></w:txbxContent></mc:Choice>'
          '<mc:Fallback><w:txbxContent><w:p><w:r><w:t>BoxText</w:t></w:r></w:p></w:txbxContent></mc:Fallback>'
          '</mc:AlternateContent></w:drawing></w:r>'
          '</w:p>'
          '</w:body></w:document>';
      final bytes = utf8.encode(docXml);
      archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
      final file = File('${fixtures.path}/textbox.docx');
      await file.writeAsBytes(ZipEncoder().encode(archive)!);

      final parsed = await ScriptNotifier().parseFile(file);
      expect(parsed.isError, isFalse);
      final words = WordAligner.tokenize(parsed.text)
          .where((w) => !w.isNewline)
          .map((w) => w.raw)
          .toList();
      expect(words, ['Outer', 'BoxText']);
    });

    test('DOCX mixed Hebrew + English run preserves w:szCs and w:cs font',
        () async {
      final archive = Archive();
      const docXml = '<w:document xmlns:w="$_wNs"><w:body>'
          '<w:p><w:pPr><w:bidi/></w:pPr>'
          '<w:r><w:rPr><w:sz w:val="22"/><w:szCs w:val="40"/>'
          '<w:rFonts w:ascii="Arial" w:cs="David"/></w:rPr>'
          '<w:t>שלום VTR</w:t></w:r></w:p>'
          '</w:body></w:document>';
      final bytes = utf8.encode(docXml);
      archive.addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
      final file = File('${fixtures.path}/mixed_cs.docx');
      await file.writeAsBytes(ZipEncoder().encode(archive)!);

      final parsed = await ScriptNotifier().parseFile(file);
      expect(parsed.isError, isFalse);
      final words = WordAligner.tokenize(parsed.text);
      expect(words.map((w) => w.fontSize), [20, 20]);
      expect(words.map((w) => w.fontFamily), ['David', 'David']);
    });

    test('RTF Hebrew unicode escapes with hex ANSI fallback do not double',
        () async {
      final file = File('${fixtures.path}/hebrew.rtf');
      await file.writeAsBytes(
        latin1.encode(
          r"{\rtf1\ansi\ansicpg1255\uc1\u1513\'f9\u1500\'ec\u1493\'e5\u1501\'ed "
          r"\u1513 \'f9 {\uc0\u1513\u1500}}",
        ),
      );
      final parsed = await ScriptNotifier().parseFile(file);
      expect(parsed.isError, isFalse);
      expect(parsed.text, 'שלום ש של');
    });

    test('PDF and ODT are excluded from import picker and fail closed in parseFile',
        () async {
      expect(PlatformFileImport.supportedExtensions, isNot(contains('pdf')));
      expect(PlatformFileImport.supportedExtensions, isNot(contains('odt')));
      expect(PlatformFileImport.formatsLabel, isNot(contains('PDF')));
      expect(PlatformFileImport.formatsLabel, isNot(contains('ODT')));

      final pdfFile = File('${fixtures.path}/sample.pdf');
      await pdfFile.writeAsBytes(utf8.encode('%PDF-1.7 binary payload'));
      final pdfParsed = await ScriptNotifier().parseFile(pdfFile);
      expect(pdfParsed.isError, isTrue);
      expect(pdfParsed.text, isEmpty);

      final odtFile = File('${fixtures.path}/sample.odt');
      await odtFile.writeAsBytes(utf8.encode('PK\x03\x04 zip payload'));
      final odtParsed = await ScriptNotifier().parseFile(odtFile);
      expect(odtParsed.isError, isTrue);
      expect(odtParsed.text, isEmpty);
    });
  });

  group('Stage 1B — 2x Invert preserves semantic colors', () {
    test('repeated whole-script invert preserves cues and remaps invisible text',
        () {
      const start =
          '[bg=#FFFF00]Important[/bg] [color=#FF0000]Cue[/color] '
          '[color=#FFFFFF]BakedWhite[/color] plain';

      // 1st invert: black bg (#000000) + white text (#FFFFFF) -> white bg + black text
      final first = EditorInlineStyleOperation.applyWholeScriptHighlightColorInvert(
        text: start,
        defaultTextColor: 'FFFFFF',
        scriptBackgroundColor: '000000',
      );
      expect(first.text, contains('[color=#FFFF00]Important[/color]'));
      expect(first.text, contains('[color=#FF0000]Cue[/color]'));
      expect(first.text, contains('[color=#000000]BakedWhite[/color]'));
      expect(first.text, endsWith('plain'));

      // 2nd invert: white bg (#FFFFFF) + black text (#000000) -> black bg + white text
      final second = EditorInlineStyleOperation.applyWholeScriptHighlightColorInvert(
        text: first.text,
        defaultTextColor: '000000',
        scriptBackgroundColor: 'FFFFFF',
      );
      expect(second.text, contains('[color=#FFFF00]Important[/color]'));
      expect(second.text, contains('[color=#FF0000]Cue[/color]'));
      expect(second.text, contains('[color=#FFFFFF]BakedWhite[/color]'));
      expect(second.text, endsWith('plain'));
    });
  });

  group('Stage 1B — Native Windows C++ runner safety contracts', () {
    test('runner sources contain null guard, non-topmost fullscreen, DPI clamp, and mutex',
        () {
      final flutterWindow = File('windows/runner/flutter_window.cpp')
          .readAsStringSync();
      expect(
        flutterWindow,
        contains('if (flutter_controller_ && flutter_controller_->engine())'),
      );
      expect(flutterWindow, isNot(contains('SetWindowPos(hwnd, HWND_TOPMOST')));
      expect(flutterWindow, contains('SetWindowPos(hwnd, HWND_TOP,'));
      expect(flutterWindow, contains('SnapFullscreenToCurrentMonitor'));

      final win32Window = File('windows/runner/win32_window.cpp')
          .readAsStringSync();
      expect(win32Window, contains('monitor_info.rcWork'));
      expect(win32Window, contains('LOWORD(wparam) != WA_INACTIVE'));

      final mainCpp = File('windows/runner/main.cpp').readAsStringSync();
      expect(mainCpp, contains('AutoTeleprompter_SingleInstance_Mutex'));
      expect(mainCpp, contains('L"AutoTeleprompter"'));
      expect(mainCpp, contains('NvOptimusEnablement = 0x00000000'));
      expect(mainCpp, contains('AmdPowerXpressRequestHighPerformance = 0'));
    });
  });
}
