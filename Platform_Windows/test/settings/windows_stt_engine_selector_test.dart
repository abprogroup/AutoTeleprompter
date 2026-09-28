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

  testWidgets('exposes only the hidden in-app speech engine', (tester) async {
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (_) {},
      ),
    );

    expect(find.byType(ChoiceChip), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(r'hidden.*in-app|in-app.*hidden', caseSensitive: false),
      ),
      findsWidgets,
    );
    expect(
      find.textContaining(
        RegExp(r'\b(edge|chrome|whisper|offline)\b', caseSensitive: false),
      ),
      findsNothing,
    );
  });

  testWidgets('legacy values still select the sole in-app choice', (
    tester,
  ) async {
    const legacyValues = <String>[
      AppSettings.sttEngineAuto,
      AppSettings.sttEngineWindowsOffline,
      AppSettings.sttEngineBrowserOnline,
      AppSettings.sttEngineBrowserExternalEdge,
      AppSettings.sttEngineBrowserExternalChrome,
      AppSettings.sttEngineWhisperTiny,
      AppSettings.sttEngineWhisperBase,
      AppSettings.sttEngineWhisperSmall,
      AppSettings.sttEngineWhisperMedium,
      'google',
      'unexpected',
    ];

    for (final value in legacyValues) {
      await tester.pumpWidget(
        buildSelector(value: value, enabled: true, onChanged: (_) {}),
      );
      final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
      expect(
        chip.selected,
        isTrue,
        reason: 'Legacy selection "$value" must map to hidden in-app speech.',
      );
    }
  });

  testWidgets('the sole choice reports Smart embedded speech', (tester) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );

    await tester.tap(find.byType(ChoiceChip));
    await tester.pump();

    expect(selected, AppSettings.sttEngineBrowserSmartCompatibility);
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

    await tester.tap(find.byType(ChoiceChip));
    await tester.pump();

    expect(selected, isNull);
  });
}
