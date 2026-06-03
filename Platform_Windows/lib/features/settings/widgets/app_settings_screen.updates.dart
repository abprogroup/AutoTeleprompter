part of 'app_settings_screen.dart';

extension _AppSettingsUpdates on _AppSettingsScreenState {
  List<Widget> _updatesSection(AppSettings settings) {
    return [
      _SettingsChoiceTile<String>(
        icon: Icons.system_update_alt_outlined,
        title: 'Preferred update channel',
        subtitle: _updateChannelDescription(settings.updateChannel),
        value: settings.updateChannel,
        choices: const [
          _SettingsChoice(
            label: 'Stable',
            value: AppSettings.updateChannelStable,
          ),
          _SettingsChoice(
            label: 'Beta',
            value: AppSettings.updateChannelBeta,
          ),
        ],
        onChanged: ref.read(settingsProvider.notifier).setUpdateChannel,
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.update_rounded,
        title: 'Search for updates on app startup',
        subtitle: settings.checkUpdatesOnStartup
            ? 'The app checks the selected channel after startup'
            : 'Updates are checked only when you press Check for update',
        value: settings.checkUpdatesOnStartup,
        onChanged: ref.read(settingsProvider.notifier).setCheckUpdatesOnStartup,
      ),
      const SizedBox(height: 8),
      _SettingsActionsTile(
        icon: Icons.download_for_offline_outlined,
        title: 'Check for update',
        subtitle: _checkingUpdates
            ? 'Checking ${settings.updateChannel} channel...'
            : _updateCheckDescription(settings.updateChannel),
        actions: [
          _SettingsAction(
            icon: Icons.refresh_rounded,
            label: _checkingUpdates ? 'Checking...' : 'Check now',
            onPressed: _checkingUpdates ? () {} : _checkForUpdatesNow,
          ),
        ],
      ),
    ];
  }

  String _updateChannelDescription(String channel) {
    switch (channel) {
      case AppSettings.updateChannelBeta:
        return 'Get beta builds when the update service publishes them';
      default:
        return 'Get stable builds when the update service publishes them';
    }
  }

  String _updateCheckDescription(String channel) {
    const current = autoTeleprompterAppVersion;
    return 'Current build $current. Checks the selected $channel channel.';
  }

  Future<void> _checkForUpdatesNow() async {
    _setCheckingUpdates(true);
    final settings = ref.read(settingsProvider);
    final result = await UpdateCheckService().check(
      channel: settings.updateChannel,
    );
    if (!mounted) return;
    _setCheckingUpdates(false);
    await _showUpdateResult(result, manual: true);
  }

  Future<void> _showUpdateResult(
    UpdateCheckResult result, {
    required bool manual,
  }) async {
    if (!manual && result.status != UpdateCheckStatus.updateAvailable) {
      return;
    }
    final title = switch (result.status) {
      UpdateCheckStatus.updateAvailable => 'Update available',
      UpdateCheckStatus.upToDate => 'No update available',
      UpdateCheckStatus.notConfigured => 'Update service not connected',
      UpdateCheckStatus.failed => 'Update check failed',
    };
    final details = <String>[
      result.message,
      'Current: ${result.currentVersion}',
      if (result.latestVersion != null) 'Latest: ${result.latestVersion}',
      if (result.publishedAt != null) 'Published: ${result.publishedAt}',
      if (result.notes != null && result.notes!.isNotEmpty) result.notes!,
    ].join('\n\n');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: SelectableText(
          details,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (result.status == UpdateCheckStatus.updateAvailable &&
              result.hasDownload)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                unawaited(_openUpdateDownload(result.downloadUrl!));
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open download'),
            ),
        ],
      ),
    );
  }

  Future<void> _openUpdateDownload(String url) async {
    try {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.openUpdateDownload',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update download could not be opened.')),
      );
    }
  }
}
