import 'package:autoteleprompter/features/script/services/editor_font_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor font service exposes real toolbar font families', () {
    expect(EditorFontService.cleanFamily(''), 'Inter');
    expect(EditorFontService.families, contains('Playfair Display'));
    expect(EditorFontService.families, contains('Courier Prime'));

    final styled = EditorFontService.applyFamily(
      const TextStyle(fontFamily: 'Inter'),
      'Merriweather',
    );
    expect(styled.fontFamily, 'Merriweather');
  });

  testWidgets('markup controller applies inline font families to visible text',
      (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(),
    ));

    final context = tester.element(find.byType(SizedBox));
    final controller = MarkupController(
      text: '[font=Playfair Display]Hello[/font]',
    );
    addTearDown(controller.dispose);

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(fontFamily: 'Inter'),
      withComposing: false,
    );
    final visibleSpan = span.children!
        .whereType<TextSpan>()
        .singleWhere((child) => child.text == 'Hello');

    expect(visibleSpan.style?.fontFamily, 'Playfair Display');
  });
}
