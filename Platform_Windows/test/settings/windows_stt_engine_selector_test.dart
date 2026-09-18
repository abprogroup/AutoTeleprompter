import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:autoteleprompter/features/settings/widgets/windows_stt_engine_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSelector({
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: WindowsSttEngineSelector(
          value: value,
          enabled: enabled,
          accentColor: const Color(0xFFFFBF00),
          onChanged: onChanged,
        ),
      ),
    );
  }

  testWidgets('shows browser strategies and the offline engine', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (_) {},
      ),
    );

    expect(find.text('Smart compatibility (recommended)'), findsOneWidget);
    expect(find.text('In-app browser only'), findsOneWidget);
    expect(find.text('Microsoft Edge only'), findsOneWidget);
    expect(find.text('Google Chrome only'), findsOneWidget);
    expect(find.text('Offline Whisper'), findsOneWidget);
    expect(
      find.text(
        'Smart chooses a compatible browser host when needed. Changes take effect on the next listening session.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('maps legacy windows_auto to the recommended Smart choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineAuto,
        enabled: true,
        onChanged: (_) {},
      ),
    );

    final smartChip = tester.widget<ChoiceChip>(
      find.descendant(
        of: find.byKey(WindowsSttEngineSelector.smartChoiceKey),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(smartChip.selected, isTrue);
  });

  testWidgets('reports explicit in-app-only selection', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(WindowsSttEngineSelector.inAppChoiceKey));
    await tester.pump();

    expect(selected, AppSettings.sttEngineBrowserOnline);
  });

  testWidgets('reports Edge selection when enabled', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(WindowsSttEngineSelector.edgeChoiceKey));
    await tester.pump();

    expect(selected, AppSettings.sttEngineBrowserExternalEdge);
  });

  testWidgets('reports Chrome selection when enabled', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(WindowsSttEngineSelector.chromeChoiceKey));
    await tester.pump();

    expect(selected, AppSettings.sttEngineBrowserExternalChrome);
  });

  testWidgets('shows an explicit persisted Chrome selection', (tester) async {
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserExternalChrome,
        enabled: true,
        onChanged: (_) {},
      ),
    );

    final chromeChip = tester.widget<ChoiceChip>(
      find.descendant(
        of: find.byKey(WindowsSttEngineSelector.chromeChoiceKey),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chromeChip.selected, isTrue);
    expect(
      find.text(
        'Always uses Google Chrome. Changes take effect on the next listening session.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reports offline Whisper selection when enabled', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(WindowsSttEngineSelector.offlineChoiceKey));
    await tester.pump();

    expect(selected, AppSettings.sttEngineWhisperTiny);
  });

  testWidgets('does not change engine while listening', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: false,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byKey(WindowsSttEngineSelector.edgeChoiceKey));
    await tester.pump();

    expect(selected, isNull);
    expect(
      find.textContaining('Stop listening to change this.'),
      findsOneWidget,
    );
  });
}
