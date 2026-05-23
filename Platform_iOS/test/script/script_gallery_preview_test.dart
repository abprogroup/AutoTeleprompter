import 'package:autoteleprompter/core/services/styling_service.dart';
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
}
