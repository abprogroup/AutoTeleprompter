import 'dart:io';

import 'package:autoteleprompter/features/settings/models/app_settings.dart';
import 'package:autoteleprompter/features/settings/providers/offline_stt_models_provider.dart';
import 'package:autoteleprompter/features/settings/widgets/windows_stt_engine_selector.dart';
import 'package:autoteleprompter/platform/stt/offline_stt_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('atp_stt_selector_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildSelector({
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    final manager = OfflineSttModelManager(
      rootDirectoryResolver: () async => tempDir,
    );
    return ProviderScope(
      overrides: [
        offlineSttModelsProvider.overrideWith(
          () => OfflineSttModelsNotifier(manager: manager),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WindowsSttEngineSelector(
              value: value,
              enabled: enabled,
              accentColor: const Color(0xFFFFBF00),
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('exposes online in-app speech and all 8 offline Sherpa engines', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineBrowserSmartCompatibility,
        enabled: true,
        onChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(9));
    expect(find.byKey(WindowsSttEngineSelector.smartChoiceKey), findsOneWidget);
    expect(
      find.byKey(WindowsSttEngineSelector.offlineNemo80StreamingKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineNemo480StreamingKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineKroko64StreamingKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineKrokoStreamingKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineZipformerFastKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineZipformerPrecisionKey),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineParakeetV3Key),
      findsOneWidget,
    );
    expect(
      find.byKey(WindowsSttEngineSelector.offlineParakeetV2Key),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r'\b(edge|chrome|whisper)\b', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('legacy values still select hidden in-app speech', (
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
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.descendant(
          of: find.byKey(WindowsSttEngineSelector.smartChoiceKey),
          matching: find.byType(ChoiceChip),
        ),
      );
      expect(
        chip.selected,
        isTrue,
        reason: 'Legacy selection "$value" must map to hidden in-app speech.',
      );
    }
  });

  testWidgets('selecting an offline engine reports ID and shows HE/EN pack controls', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      buildSelector(
        value: AppSettings.sttEngineOfflineZipformerFast,
        enabled: true,
        onChanged: (value) => selected = value,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HE'), findsOneWidget);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Download HE + EN'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(2));
    final boostSwitch = find.byKey(
      WindowsSttEngineSelector.scriptBoostSwitchKey,
    );
    expect(boostSwitch, findsOneWidget);

    await tester.ensureVisible(boostSwitch);
    await tester.pumpAndSettle();
    await tester.tap(boostSwitch);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Raw greedy decoding'),
      findsOneWidget,
    );

    final parakeetChip = find.byKey(
      WindowsSttEngineSelector.offlineParakeetV3Key,
    );
    await tester.ensureVisible(parakeetChip);
    await tester.pumpAndSettle();
    await tester.tap(parakeetChip);
    await tester.pump();
    expect(selected, AppSettings.sttEngineOfflineParakeetV3);
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
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(WindowsSttEngineSelector.offlineZipformerFastKey),
    );
    await tester.pump();

    expect(selected, isNull);
  });
}
