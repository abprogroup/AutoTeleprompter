import 'dart:io';

import 'package:autoteleprompter/features/script/widgets/teleprompt_selector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selector sheet builds before async recent folder load completes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('selector_sheet_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelepromptSelectorSheet(initialPath: tempDir.path),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SELECT SCRIPT'), findsOneWidget);
    expect(find.textContaining(tempDir.path), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
