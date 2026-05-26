import 'package:autoteleprompter/features/settings/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('login seed uses email prefix when display name is still Guest',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .seedDisplayNameFromEmail('speaker.name@example.com');

    expect(container.read(settingsProvider).displayName, 'speaker.name');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'speaker.name');
  });

  test('login seed preserves an existing custom display name', () async {
    SharedPreferences.setMockInitialValues({'displayName': 'Amit'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .seedDisplayNameFromEmail('speaker.name@example.com');

    expect(container.read(settingsProvider).displayName, 'Amit');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('displayName'), 'Amit');
  });
}
