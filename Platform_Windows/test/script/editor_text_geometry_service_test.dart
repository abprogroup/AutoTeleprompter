import 'package:autoteleprompter/features/script/services/editor_text_geometry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Hebrew empty row between Hebrew blocks resolves RTL', () {
    final blocks = [
      '\u05e9\u05d5\u05e8\u05d4 \u05e8\u05d0\u05e9\u05d5\u05e0\u05d4',
      '',
      '[u]\u05e9\u05d5\u05e8\u05d4 \u05e9\u05e0\u05d9\u05d4[/u]',
    ];

    expect(EditorTextGeometryService.resolveBlockRtl(blocks, 1), isTrue);
  });

  test('English empty row between English blocks resolves LTR', () {
    final blocks = [
      'First line',
      '[bg=#00FF00]   [/bg]',
      'Second line',
    ];

    expect(EditorTextGeometryService.resolveBlockRtl(blocks, 1), isFalse);
  });

  test('empty script defaults to LTR', () {
    expect(EditorTextGeometryService.resolveBlockRtl(['', '   '], 0), isFalse);
    expect(EditorTextGeometryService.resolveBlockRtl(['', '   '], 1), isFalse);
  });

  test('explicit alignment overrides resolved direction alignment', () {
    expect(
      EditorTextGeometryService.resolveTextAlign(
        '[align=center]\u05e9\u05dc\u05d5\u05dd[/align=center]',
        isRtl: true,
      ),
      TextAlign.center,
    );
    expect(
      EditorTextGeometryService.resolveTextAlign('', isRtl: true),
      TextAlign.right,
    );
    expect(
      EditorTextGeometryService.resolveTextAlign('', isRtl: false),
      TextAlign.left,
    );
  });
}
