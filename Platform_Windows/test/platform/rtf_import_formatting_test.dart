import 'dart:convert';
import 'dart:io';

import 'package:autoteleprompter/features/script/providers/script_provider.dart';
import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:autoteleprompter/features/teleprompter/services/word_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixtures;

  setUp(() async {
    fixtures = await Directory.systemTemp.createTemp('autoteleprompter_rtf_');
  });

  tearDown(() async {
    await fixtures.delete(recursive: true);
  });

  Future<ParsedFile> parse(String rtf, {String extension = 'rtf'}) async {
    final file = File('${fixtures.path}/script.$extension');
    await file.writeAsBytes(latin1.encode(rtf));
    final result = await ScriptNotifier().parseFile(file);
    expect(result.isError, isFalse, reason: result.errorMessage);
    return result;
  }

  test(
    'underline off at the start leaves ordinary paragraphs unstyled',
    () async {
      final result = await parse(r'{\rtf1\ansi\ul0 First\par Second}');
      expect(result.text, 'First\nSecond');
    },
  );

  test('ul0 ends only the explicitly underlined run', () async {
    final result = await parse(
      r'{\rtf1\ansi Plain \ul Underlined\ul0  plain\par Normal}',
    );
    expect(result.text, 'Plain [u]Underlined[/u] plain\nNormal');
  });

  test('ulnone remains a supported underline reset', () async {
    final result = await parse(r'{\rtf1\ul Yes\ulnone  no}');
    expect(result.text, '[u]Yes[/u] no');
  });

  test('closing a group stops underline without requiring ulnone', () async {
    final result = await parse(
      r'{\rtf1\ansi Before {\ul Only this} after\par Normal}',
    );
    expect(result.text, 'Before [u]Only this[/u] after\nNormal');
  });

  test('nested underline-off group restores its underlined parent', () async {
    final result = await parse(r'{\rtf1 Plain {\ul A {\ul0 B} C} D}');
    expect(result.text, 'Plain [u]A [/u]B[u] C[/u] D');
  });

  test(
    'plain reset inside a group does not erase its parent formatting',
    () async {
      final result = await parse(
        r'{\rtf1\b\i\ul Parent {\plain Normal} Parent}',
      );
      expect(
        result.text,
        '**[i][u]Parent [/u][/i]**Normal**[i][u] Parent[/u][/i]**',
      );
    },
  );

  test('nested bold and italic are restored with underline', () async {
    final result = await parse(r'{\rtf1 {\ul U {\b B {\i I} B} U} N}');
    expect(
      result.text,
      '[u]U [/u]**[u]B [/u]****[i][u]I[/u][/i]**'
      '**[u] B[/u]**[u] U[/u] N',
    );
  });

  test('group-scoped colors, highlight, font and size do not leak', () async {
    final result = await parse(
      r'{\rtf1{\fonttbl{\f0 Arial;}{\f1 Courier New;}}'
      r'{\colortbl;\red255\green0\blue0;\red255\green0\blue255;}'
      r'\f0\fs24 Before {\f1\fs40\cf1\highlight2\ul Marked} After}',
    );
    expect(
      result.text,
      '[font=Arial][size=12]Before [/size][/font]'
      '[u][font=Courier New][size=20][bg=#FF00FF][color=#FF0000]'
      'Marked[/color][/bg][/size][/font][/u]'
      '[font=Arial][size=12] After[/size][/font]',
    );
  });

  test('paragraph alignment is restored after an inner group', () async {
    final result = await parse(r'{\rtf1\qr Right\par{\qc Centre\par}Right}');
    expect(
      result.text,
      '[align=right]Right[/align=right]\n'
      '[align=center]Centre[/align=center]\n'
      '[align=right]Right[/align=right]',
    );
  });

  test('ignored destinations do not change style or expose metadata', () async {
    final result = await parse(
      r'{\rtf1{\stylesheet{\ul Hidden;}}Plain '
      r'{\ul A{\*\private\ul0 secret {\b hidden}} B} Normal}',
    );
    expect(result.text, 'Plain [u]A B[/u] Normal');
  });

  test('escaped literal braces do not pop formatting groups', () async {
    final result = await parse(r'{\rtf1 {\ul A\{B\}C} normal}');
    expect(result.text, '[u]A{B}C[/u] normal');
  });

  test('escaped braces in ignored metadata do not end its group early',
      () async {
    final result = await parse(
      r'{\rtf1 Plain {\ul A{\*\private ignored\} \ul0 hidden} B} Normal}',
    );
    expect(result.text, 'Plain [u]A B[/u] Normal');
  });

  test('paragraph breaks preserve intentional continuing underline', () async {
    final result = await parse(r'{\rtf1\ul First\par Second\ul0\par Normal}');
    expect(result.text, '[u]First[/u]\n[u]Second[/u]\nNormal');
  });

  test(
    'RTF with a DOC extension uses the same scoped formatting rules',
    () async {
      final result = await parse(
        r'{\rtf1\ul0 Plain {\ul Title} Normal}',
        extension: 'doc',
      );
      expect(result.text, 'Plain [u]Title[/u] Normal');
    },
  );

  test(
    'Hebrew code-page text retains underline only on its intended words',
    () async {
      final result = await parse(
        r"{\rtf1\ansi\ansicpg1255\ul0 \'f9\'ec\'e5\'ed "
        r"{\ul \'f2\'e5\'ec\'ed} \'f8\'e2\'e9\'ec}",
      );
      expect(result.text, 'שלום [u]עולם[/u] רגיל');
      final words = WordAligner.tokenize(result.text);
      expect(words.map((word) => word.raw), ['שלום', 'עולם', 'רגיל']);
      expect(words.map((word) => word.isUnderline), [false, true, false]);
      expect(words.every((word) => word.isRtl), isTrue);
      final editorRanges = MarkupDecorationParser.decorationRanges(result.text);
      expect(editorRanges, hasLength(1));
      expect(editorRanges.single.type, MarkupDecorationType.underline);
      expect(
        result.text.substring(editorRanges.single.start, editorRanges.single.end),
        'עולם',
      );
    },
  );

  test(
    'Unicode Hebrew with mixed English keeps the same style boundaries',
    () async {
      final result = await parse(
        r'{\rtf1\ansi\uc1\ul0 Normal '
        r'{\ul \u1513?\u1500?\u1493?\u1501?} after}',
      );
      expect(result.text, 'Normal [u]שלום[/u] after');
      final words = WordAligner.tokenize(result.text);
      expect(words.map((word) => word.isUnderline), [false, true, false]);
    },
  );
}
