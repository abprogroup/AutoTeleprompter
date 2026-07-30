part of 'app_settings_screen.dart';

extension _AppSettingsUpdates on _AppSettingsScreenState {
  bool get _updateBusy => _checkingUpdates || _downloadingUpdate;
  bool get _adminUpdateConfigured =>
      autoTeleprompterAdminEmail.trim().isNotEmpty &&
      autoTeleprompterAdminCodeHash.trim().isNotEmpty;

  String _effectiveUpdateChannel(String channel, AuthState auth) {
    if (channel != AppSettings.updateChannelInternal) return channel;
    return auth.isAdmin &&
            (auth.accountBackendEnabled || _adminUpdateConfigured)
        ? AppSettings.updateChannelInternal
        : AppSettings.updateChannelStable;
  }

  List<Widget> _updatesSection(AppSettings settings, AuthState auth) {
    final showInternal =
        auth.isAdmin && (auth.accountBackendEnabled || _adminUpdateConfigured);
    final effectiveChannel = _effectiveUpdateChannel(
      settings.updateChannel,
      auth,
    );

    return [
      _SettingsTile(
        icon: Icons.system_update_alt_outlined,
        title: 'Preferred update channel',
        subtitle: _updateChannelLabel(effectiveChannel),
        onTap: () => _pickUpdateChannel(showInternal, settings.updateChannel),
      ),
      const SizedBox(height: 8),
      _SettingsSwitchTile(
        icon: Icons.update_rounded,
        title: 'Search for updates on app startup',
        subtitle: settings.checkUpdatesOnStartup
            ? 'The app checks the selected channel after startup'
            : 'Updates are checked only when you press Check for update',
        value: settings.checkUpdatesOnStartup,
        onChanged: (value) =>
            ref.read(settingsProvider.notifier).setCheckUpdatesOnStartup(value),
      ),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.download_for_offline_outlined,
        title: _checkingUpdates ? 'Checking...' : 'Check for update',
        subtitle: _checkingUpdates
            ? 'Checking $effectiveChannel channel...'
            : _downloadingUpdate
                ? 'Downloading update package...'
                : 'Current build $autoTeleprompterAppVersion. Checks the '
                    'selected $effectiveChannel channel.',
        onTap: _updateBusy ? null : () => _checkForUpdatesNow(auth),
      ),
    ];
  }

  String _updateChannelLabel(String channel) {
    switch (channel) {
      case AppSettings.updateChannelBeta:
        return 'Beta - get beta builds when published';
      case AppSettings.updateChannelInternal:
        return 'Internal - admin-only private builds';
      default:
        return 'Stable - get stable builds when published';
    }
  }

  Future<void> _pickUpdateChannel(
    bool showInternal,
    String currentChannel,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Preferred update channel',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final channel in [
              AppSettings.updateChannelStable,
              AppSettings.updateChannelBeta,
              if (showInternal) AppSettings.updateChannelInternal,
            ])
              RadioListTile<String>(
                value: channel,
                // ignore: deprecated_member_use
                groupValue: currentChannel,
                activeColor: const Color(0xFFFFBF00),
                title: Text(
                  _updateChannelLabel(channel),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                // ignore: deprecated_member_use
                onChanged: (value) => Navigator.pop(ctx, value),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected != null && selected != currentChannel) {
      await ref.read(settingsProvider.notifier).setUpdateChannel(selected);
    }
  }

  Future<void> _checkForUpdatesNow(AuthState auth) async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    final settings = ref.read(settingsProvider);
    final result = await UpdateCheckService().check(
      channel: _effectiveUpdateChannel(settings.updateChannel, auth),
    );
    if (!mounted) return;
    setState(() => _checkingUpdates = false);
    await _showUpdateResult(result);
  }

  Future<void> _showUpdateResult(UpdateCheckResult result) async {
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
    if (!mounted) return;
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
    setState(() => _downloadingUpdate = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Downloading update package...')),
    );
    try {
      final file = await UpdateDownloadService().download(result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening Android installer for the update...'),
        ),
      );
      await UpdateInstallService().installDownloadedUpdate(file, result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update install failed: ${sanitizeSettingsErrorForUser(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFFFBF00),
          ),
        ],
      ),
    );
  }
}
