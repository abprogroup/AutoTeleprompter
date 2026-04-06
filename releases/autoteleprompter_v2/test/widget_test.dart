import 'package:flutter_test/flutter_test.dart';
import 'package:autoteleprompt/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AutoTelepromptApp()));
    expect(find.text('AutoTeleprompt'), findsOneWidget);
  });
}
