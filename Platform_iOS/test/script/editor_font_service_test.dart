import 'package:autoteleprompter/features/script/services/editor_font_service.dart';
import 'package:autoteleprompter/features/script/services/markup_decoration_service.dart';
import 'package:autoteleprompter/features/script/widgets/editor/markup_controller.dart';
import 'package:autoteleprompter/features/script/widgets/editor/styling_logic_mixin.dart';
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

  testWidgets('font command can reapply selected text repeatedly',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _StylingHarness()));
    final state =
        tester.state<_StylingHarnessState>(find.byType(_StylingHarness));

    final controller = MarkupController(text: 'Hello world')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    state.attachControllers([controller]);

    state.applyInlineProperty(
      'font',
      '[font=Lora]',
      '[/font]',
      skipHistory: true,
    );
    expect(controller.text, '[font=Lora]Hello[/font] world');
    expect(controller.selection.textInside(controller.text), 'Hello');

    state.applyInlineProperty(
      'font',
      '[font=Roboto]',
      '[/font]',
      skipHistory: true,
    );
    expect(controller.text, '[font=Roboto]Hello[/font] world');
    expect(controller.selection.textInside(controller.text), 'Hello');
  });
}

class _StylingHarness extends StatefulWidget {
  const _StylingHarness();

  @override
  State<_StylingHarness> createState() => _StylingHarnessState();
}

class _StylingHarnessState extends State<_StylingHarness>
    with StylingLogicMixin<_StylingHarness> {
  List<MarkupController> _controllers = [];
  MarkupController? _activeController;
  bool _isGlobalSelection = false;
  bool _isCleaning = false;

  void attachControllers(List<MarkupController> controllers) {
    _controllers = controllers;
    _activeController = controllers.isEmpty ? null : controllers.first;
  }

  @override
  List<MarkupController> get controllers => _controllers;

  @override
  MarkupController? get activeController => _activeController;

  @override
  bool get isGlobalSelection => _isGlobalSelection;

  @override
  set isGlobalSelection(bool value) => _isGlobalSelection = value;

  @override
  bool get isCleaning => _isCleaning;

  @override
  set isCleaning(bool value) => _isCleaning = value;

  @override
  void saveHistory({required String description, bool debounce = true}) {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
