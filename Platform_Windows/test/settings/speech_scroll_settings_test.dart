import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _load([Map<String, Object>? values]) async {
  if (values != null) SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('displayName', 'scroll-test-loaded');
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(settingsProvider);
  for (var i = 0; i < 100; i++) {
    if (container.read(settingsProvider).displayName == 'scroll-test-loaded') {
      return container;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Settings did not finish loading.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'old installs and model defaults retain existing speech scroll tuning',
    () async {
      final container = await _load({'scrollSpeed': 175.0});
      final loaded = container.read(settingsProvider);
      const defaults = AppSettings();
      expect(loaded.speechScrollSmoothness, defaults.speechScrollSmoothness);
      expect(loaded.speechScrollSpeed, defaults.speechScrollSpeed);
      expect(loaded.speechScrollSmoothness, 0.5);
      expect(loaded.speechScrollSpeed, 1);
      expect(loaded.scrollSpeed, 175);
    },
  );

  test(
    'both sliders persist independently across reload and copyWith',
    () async {
      final container = await _load({});
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setSpeechScrollSmoothness(0.85);
      await notifier.setSpeechScrollSpeed(1.65);
      await notifier.setFontSize(38);
      final reloaded = await _load();
      final settings = reloaded.read(settingsProvider);
      expect(settings.speechScrollSmoothness, 0.85);
      expect(settings.speechScrollSpeed, 1.65);
      expect(settings.fontSize, 38);
      expect(
        settings.copyWith(scrollMode: 'manual').speechScrollSmoothness,
        0.85,
      );
      expect(settings.copyWith(scrollMode: 'manual').speechScrollSpeed, 1.65);
    },
  );

  test(
    'reset only touches its own value, never speech or manual-speed settings',
    () async {
      final container = await _load({
        'speechScrollSmoothness': 0.8,
        'speechScrollSpeed': 1.7,
        'scrollSpeed': -120.0,
        'sttManualProfileEnabled': true,
        'sttManualStartAdvanceSmallWords': 6,
        'sttVisibleSkipEnabled': true,
        'allowScrollDuringActiveSession': true,
      });
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setSpeechScrollSmoothness(
        AppSettings.defaultSpeechScrollSmoothness,
      );
      expect(container.read(settingsProvider).speechScrollSmoothness, 0.5);
      expect(container.read(settingsProvider).speechScrollSpeed, 1.7);
      await notifier.setSpeechScrollSmoothness(0.75);
      await notifier.setSpeechScrollSpeed(AppSettings.defaultSpeechScrollSpeed);
      final settings = container.read(settingsProvider);
      expect(settings.speechScrollSmoothness, 0.75);
      expect(settings.speechScrollSpeed, 1);
      expect(settings.scrollSpeed, -120);
      expect(settings.scrollMode, 'auto');
      expect(
        settings.sttEngine,
        AppSettings.sttEngineBrowserSmartCompatibility,
      );
      expect(settings.sttManualProfileEnabled, isTrue);
      expect(settings.sttManualStartAdvanceSmallWords, 6);
      expect(settings.sttVisibleSkipEnabled, isTrue);
      expect(settings.allowScrollDuringActiveSession, isTrue);
      final reloaded = await _load();
      expect(reloaded.read(settingsProvider).speechScrollSmoothness, 0.75);
      expect(reloaded.read(settingsProvider).speechScrollSpeed, 1);
    },
  );

  test(
    'malformed saved types use defaults instead of breaking settings load',
    () async {
      final container = await _load({
        'speechScrollSmoothness': 'invalid',
        'speechScrollSpeed': true,
      });
      expect(container.read(settingsProvider).speechScrollSmoothness, 0.5);
      expect(container.read(settingsProvider).speechScrollSpeed, 1);
    },
  );

  test('saved numbers outside the allowed ranges are clamped', () async {
    final container = await _load({
      'speechScrollSmoothness': 99,
      'speechScrollSpeed': -1,
    });
    expect(container.read(settingsProvider).speechScrollSmoothness, 1);
    expect(container.read(settingsProvider).speechScrollSpeed, 0.25);
  });

  test(
    'setters sanitize ranges and non-finite input before persistence',
    () async {
      final container = await _load({});
      final notifier = container.read(settingsProvider.notifier);
      final prefs = await SharedPreferences.getInstance();
      await notifier.setSpeechScrollSmoothness(-1);
      await notifier.setSpeechScrollSpeed(999);
      expect(prefs.getDouble('speechScrollSmoothness'), 0);
      expect(prefs.getDouble('speechScrollSpeed'), 2);
      await notifier.setSpeechScrollSmoothness(double.nan);
      await notifier.setSpeechScrollSpeed(double.infinity);
      expect(prefs.getDouble('speechScrollSmoothness'), 0.5);
      expect(prefs.getDouble('speechScrollSpeed'), 1);
    },
  );
}
