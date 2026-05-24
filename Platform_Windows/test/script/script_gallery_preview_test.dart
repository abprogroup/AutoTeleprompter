import 'package:autoteleprompter/features/script/services/styling_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recent preview uses first two non-empty visible lines', () {
    final preview = StylingService.recentScriptPreviewText(
      fullText: '\n\n[align=right]\nשלום עולם\nשורה שניה\nשורה שלישית',
    );

    expect(preview, 'שלום עולם\nשורה שניה');
  });

  test('recent preview strips markup and ignores empty snippet', () {
    final preview = StylingService.recentScriptPreviewText(
      snippet: '   ',
      fullText: '[bg=#805000]EP1: Intro[/bg]\n[u]Imported text[/u]',
    );

    expect(preview, 'EP1: Intro\nImported text');
  });

  test('direction changes preserve alignment markup', () {
    const text = '[align=center][rtl]שלום[/rtl][/align=center]';
    final next = StylingService.applyDirection(
      text,
      const TextSelection.collapsed(offset: 0),
      'ltr',
    );

    expect(next, '[ltr][align=center]שלום[/align=center][/ltr]');
  });

  test('alignment changes preserve direction markup', () {
    const text = '[rtl][align=center]שלום[/align=center][/rtl]';
    final next = StylingService.applyLayout(
      text,
      const TextSelection.collapsed(offset: 0),
      'right',
    );

    expect(next, '[right][rtl]שלום[/rtl][/right]');
  });
}
