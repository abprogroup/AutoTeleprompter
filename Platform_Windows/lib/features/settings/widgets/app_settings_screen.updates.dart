part of 'app_settings_screen.dart';

extension _AppSettingsUpdates on _AppSettingsScreenState {
  List<Widget> _updatesSection(AppSettings settings) {
    final auth = ref.watch(authProvider);
    final adminUpdateConfigured =
        autoTeleprompterAdminEmail.trim().isNotEmpty &&
            autoTeleprompterAdminCodeHash.trim().isNotEmpty;
    final showInternal =
        auth.isAdmin && (auth.accountBackendEnabled || adminUpdateConfigured);
    final effectiveChannel = _effectiveUpdateChannel(settings.updateChannel);
    final choices = <_SettingsChoice<String>>[
      const _SettingsChoice(
        label: 'Stable',
        value: AppSettings.updateChannelStable,
      ),
      const _SettingsChoice(
        label: 'Beta',
        value: AppSettings.updateChannelBeta,
      ),
      if (showInternal)
        const _SettingsChoice(
          label: 'Internal',
          value: AppSettings.updateChannelInternal,
        ),
    ];
    return [
      _SettingsChoiceTile<String>(
        icon: Icons.system_update_alt_outlined,
        title: 'Preferred update channel',
        subtitle: _updateChannelDescription(effectiveChannel),
        value: effectiveChannel,
        choices: choices,
        onChanged: ref.read(settingsProvider.notifier).setUpdateChannel,
      ),
      if (auth.isAdmin &&
          !auth.accountBackendEnabled &&
          !adminUpdateConfigured) ...[
        const SizedBox(height: 8),
        const _SettingsTile(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Internal channel not configured',
          subtitle:
              'Admin update builds need admin email and code hash defines.',
        ),
      ],
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
            ? 'Checking $effectiveChannel channel...'
            : _downloadingUpdate
                ? 'Downloading update package...'
                : _updateCheckDescription(effectiveChannel),
        actions: [
          _SettingsAction(
            icon: Icons.refresh_rounded,
            label: _checkingUpdates ? 'Checking...' : 'Check now',
            onPressed: _checkingUpdates || _downloadingUpdate
                ? null
                : _checkForUpdatesNow,
          ),
        ],
      ),
    ];
  }

  String _updateChannelDescription(String channel) {
    switch (channel) {
      case AppSettings.updateChannelBeta:
        return 'Get beta builds when the update service publishes them';
      case AppSettings.updateChannelInternal:
        return 'Admin-only private builds from the internal release hub';
      default:
        return 'Get stable builds when the update service publishes them';
    }
  }

  String _updateCheckDescription(String channel) {
    const current = autoTeleprompterAppVersion;
    return 'Current build $current. Checks the selected $channel channel.';
  }

  Future<void> _checkForUpdatesNow() async {
    if (_checkingUpdates || _downloadingUpdate) return;
    _setCheckingUpdates(true);
    final settings = ref.read(settingsProvider);
    final result = await UpdateCheckService().check(
      channel: _effectiveUpdateChannel(settings.updateChannel),
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
                unawaited(_downloadUpdatePackage(result));
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Install update'),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadUpdatePackage(UpdateCheckResult result) async {
    if (_downloadingUpdate) return;
    _setDownloadingUpdate(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading update package...')),
    );
    try {
      final file = await UpdateDownloadService().download(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Installing update. AutoTeleprompter will restart.'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await UpdateInstallService().installDownloadedUpdate(file, result);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'settings.downloadUpdatePackage',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update install failed: $error')),
      );
    } finally {
      _setDownloadingUpdate(false);
    }
  }

  String _effectiveUpdateChannel(String channel) {
    if (channel != AppSettings.updateChannelInternal) return channel;
    final auth = ref.read(authProvider);
    final adminUpdateConfigured =
        autoTeleprompterAdminEmail.trim().isNotEmpty &&
            autoTeleprompterAdminCodeHash.trim().isNotEmpty;
    return auth.isAdmin && (auth.accountBackendEnabled || adminUpdateConfigured)
        ? AppSettings.updateChannelInternal
        : AppSettings.updateChannelStable;
  }
}
