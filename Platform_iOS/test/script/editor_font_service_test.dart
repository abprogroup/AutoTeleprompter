import 'package:autoteleprompter/features/script/services/editor_font_service.dart';
import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('EditorFontService cleans empty font families to Inter', () {
    expect(EditorFontService.cleanFamily(''), EditorFontService.defaultFamily);
    expect(
        EditorFontService.cleanFamily('  '), EditorFontService.defaultFamily);
    expect(EditorFontService.cleanFamily('Lora'), 'Lora');
  });

  test('EditorFontService exposes every bundled editor font family', () {
    expect(
      EditorFontService.families,
      containsAll([
        'Inter',
        'Bebas Neue',
        'Roboto',
        'Outfit',
        'Montserrat',
        'Playfair Display',
        'Merriweather',
        'Lora',
        'Courier Prime',
      ]),
    );
  });

  test('markup visible span applies cleaned font family tags', () {
    final span = MarkupDecorationParser.visibleTextSpan(
      '[font=Lora]Hello[/font] world',
      style: const TextStyle(fontFamily: 'Inter'),
    );

    final children = span.children!.cast<TextSpan>();
    expect(children.first.text, 'Hello');
    expect(children.first.style!.fontFamily, 'Lora');
    expect(children.last.text, ' world');
    expect(children.last.style!.fontFamily, 'Inter');
  });
}
