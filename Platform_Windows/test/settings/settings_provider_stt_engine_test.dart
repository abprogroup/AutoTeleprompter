import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads a persisted windows_auto value as Smart compatibility', () async {
    SharedPreferences.setMockInitialValues({
      'sttEngine': AppSettings.sttEngineAuto,
      'displayName': 'Loaded settings marker',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);

    for (var attempt = 0; attempt < 100; attempt++) {
      if (container.read(settingsProvider).displayName ==
          'Loaded settings marker') {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      container.read(settingsProvider).displayName,
      'Loaded settings marker',
    );
    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineBrowserSmartCompatibility,
    );
  });

  test('setSttEngine normalizes legacy auto and persists Smart', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(settingsProvider.notifier)
        .setSttEngine(AppSettings.sttEngineAuto);

    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineBrowserSmartCompatibility,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('sttEngine'),
      AppSettings.sttEngineBrowserSmartCompatibility,
    );
  });

  test('setSttEngine preserves explicit browser and offline modes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);

    final notifier = container.read(settingsProvider.notifier);
    final prefs = await SharedPreferences.getInstance();

    await notifier.setSttEngine(AppSettings.sttEngineBrowserOnline);
    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineBrowserOnline,
    );
    expect(prefs.getString('sttEngine'), AppSettings.sttEngineBrowserOnline);

    await notifier.setSttEngine(AppSettings.sttEngineBrowserExternalEdge);
    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineBrowserExternalEdge,
    );
    expect(
      prefs.getString('sttEngine'),
      AppSettings.sttEngineBrowserExternalEdge,
    );

    await notifier.setSttEngine(AppSettings.sttEngineBrowserExternalChrome);
    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineBrowserExternalChrome,
    );
    expect(
      prefs.getString('sttEngine'),
      AppSettings.sttEngineBrowserExternalChrome,
    );

    await notifier.setSttEngine(AppSettings.sttEngineWhisperTiny);
    expect(
      container.read(settingsProvider).sttEngine,
      AppSettings.sttEngineWhisperTiny,
    );
    expect(prefs.getString('sttEngine'), AppSettings.sttEngineWhisperTiny);
  });
}
