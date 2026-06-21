import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('settings load sanitizes stale unsupported STT engine values', () async {
    SharedPreferences.setMockInitialValues({'sttEngine': 'whisper_base'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(settingsProvider).sttEngine, 'google');
  });

  test('setSttEngine persists only currently supported iOS engine', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .setSttEngine('whisper_tiny');

    final prefs = await SharedPreferences.getInstance();
    expect(container.read(settingsProvider).sttEngine, 'google');
    expect(prefs.getString('sttEngine'), 'google');
  });
}
