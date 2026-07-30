part of 'settings_provider.dart';

mixin SettingsNotifierUpdate on Notifier<AppSettings> {
  Future<void> setUpdateChannel(String channel) async {
    state = state.copyWith(updateChannel: channel);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updateChannelKey, channel);
  }

  Future<void> setCheckUpdatesOnStartup(bool enabled) async {
    state = state.copyWith(checkUpdatesOnStartup: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_checkUpdatesOnStartupKey, enabled);
  }
}
