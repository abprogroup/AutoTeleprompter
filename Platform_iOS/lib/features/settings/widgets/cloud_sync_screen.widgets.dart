part of 'cloud_sync_screen.dart';

class _CloudScriptPayload {
  final String title;
  final String text;
  final String? sourcePath;
  final String? sourceType;
  final String? sessionId;
  final String? historyJson;
  final int? historyIndex;
  final double? fontSize;
  final String? fontFamily;
  final double? lineSpacing;
  final double? letterSpacing;
  final double? wordSpacing;
  final String? textAlign;
  final int? scriptBgColor;
  final int? currentWordColor;
  final int? futureWordColor;
  final bool? isRtl;
  final List<ScriptBookmark> bookmarks;
  final String identity;

  const _CloudScriptPayload({
    required this.title,
    required this.text,
    required this.sourcePath,
    required this.sourceType,
    required this.sessionId,
    required this.historyJson,
    required this.historyIndex,
    required this.fontSize,
    required this.fontFamily,
    required this.lineSpacing,
    required this.letterSpacing,
    required this.wordSpacing,
    required this.textAlign,
    required this.scriptBgColor,
    required this.currentWordColor,
    required this.futureWordColor,
    required this.isRtl,
    required this.bookmarks,
    required this.identity,
  });
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFFFBF00),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _CloudDisclosureNote extends StatelessWidget {
  const _CloudDisclosureNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFBF00).withValues(alpha: .2)),
      ),
      child: const Text(
        'Cloud disclosure: Google Drive and Dropbox account connections use '
        'the selected provider account and its terms. Online sync stores '
        'readable script files plus AutoTeleprompter restore metadata for '
        'bookmarks, highlights, history, and script settings. Local Backup '
        'writes readable script files to one folder on this device. '
        'AutoTeleprompter Cloud is planned for a later account release.',
        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _CloudActionBar extends StatelessWidget {
  final bool enabled;
  final bool syncing;
  final VoidCallback onSyncScripts;
  final VoidCallback onSyncWithApp;

  const _CloudActionBar({
    required this.enabled,
    required this.syncing,
    required this.onSyncScripts,
    required this.onSyncWithApp,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: enabled ? onSyncScripts : null,
          icon: Icon(
              syncing ? Icons.sync_problem_rounded : Icons.cloud_sync_outlined),
          label: Text(syncing ? 'Syncing scripts...' : 'Sync scripts'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFBF00),
            foregroundColor: Colors.black,
          ),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? onSyncWithApp : null,
          icon: const Icon(Icons.sync_alt_rounded, size: 18),
          label: const Text('Sync with App'),
        ),
        const Text(
          'Sync scripts updates readable files and restore metadata in '
          'connected cloud accounts, plus readable files in Local Backup. '
          'Upload script remains available for selected manual uploads.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _LocalBackupCard extends StatelessWidget {
  final CloudProviderConnection connection;
  final bool enabled;
  final VoidCallback onChoose;
  final VoidCallback? onOpen;
  final VoidCallback? onForget;
  final VoidCallback? onUpload;
  final VoidCallback? onList;
  final VoidCallback? onSyncWithApp;

  const _LocalBackupCard({
    required this.connection,
    required this.enabled,
    required this.onChoose,
    required this.onOpen,
    required this.onForget,
    required this.onUpload,
    required this.onList,
    required this.onSyncWithApp,
  });

  @override
  Widget build(BuildContext context) {
    final connected = connection.isConnected;
    final effectiveConnected = enabled && connected;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? const Color(0xFFFFBF00).withValues(alpha: .35)
              : Colors.white.withValues(alpha: .06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.folder_copy_outlined,
              color: Color(0xFFFFBF00), size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local Backup',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  !enabled
                      ? 'Connect a Pro account to use Local Backup.'
                      : connected
                          ? 'Folder: ${connection.folderPath}'
                          : 'Choose one local folder for Pro backup and provider '
                              'desktop sync folders.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: enabled ? onChoose : null,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(
                        connected ? 'Change folder' : 'Choose folder',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFBF00),
                        foregroundColor: Colors.black,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? onOpen : null,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? onForget : null,
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Forget folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? onUpload : null,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Upload script'),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? onList : null,
                      icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: const Text('Synced scripts'),
                    ),
                    OutlinedButton.icon(
                      onPressed: enabled ? onSyncWithApp : null,
                      icon: const Icon(Icons.sync_alt_rounded, size: 18),
                      label: const Text('Sync with App'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (effectiveConnected)
            const _StatusPill(
              label: 'LINKED',
              color: Colors.greenAccent,
              background: Colors.green,
            ),
        ],
      ),
    );
  }
}

class _DeletedScriptsFolderCard extends StatelessWidget {
  final bool enabled;
  final bool useCustomFolder;
  final String folderPath;
  final ValueChanged<bool> onToggleCustomFolder;
  final VoidCallback onChoose;
  final VoidCallback? onOpen;
  final VoidCallback? onForget;

  const _DeletedScriptsFolderCard({
    required this.enabled,
    required this.useCustomFolder,
    required this.folderPath,
    required this.onToggleCustomFolder,
    required this.onChoose,
    required this.onOpen,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final hasFolder = folderPath.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.restore_from_trash_outlined,
            color: Color(0xFFFFBF00),
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deleted Scripts folder',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  !enabled
                      ? 'Connect a Pro account to view or manage deleted-script backups.'
                      : hasFolder
                          ? 'Folder: $folderPath'
                          : 'Uses Local Backup/Deleted Scripts unless you choose a separate folder.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: useCustomFolder,
                  onChanged: enabled
                      ? (value) => onToggleCustomFolder(value ?? false)
                      : null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFFFFBF00),
                  checkColor: Colors.black,
                  title: const Text(
                    'Select a different folder for deleted scripts',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                if (useCustomFolder) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: enabled ? onChoose : null,
                        icon: const Icon(Icons.folder_open_outlined),
                        label:
                            Text(hasFolder ? 'Change folder' : 'Choose folder'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFBF00),
                          foregroundColor: Colors.black,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled ? onOpen : null,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open folder'),
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled ? onForget : null,
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('Forget folder'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (enabled && hasFolder)
            _StatusPill(
              label: useCustomFolder ? 'CUSTOM' : 'DEFAULT',
              color: Colors.greenAccent,
              background: Colors.green,
            ),
        ],
      ),
    );
  }
}

class _CloudOption extends StatelessWidget {
  final CloudProviderConnection connection;
  final CloudAccountInfo? account;
  final VoidCallback? onConnectAccount;
  final VoidCallback? onUploadAccount;
  final VoidCallback? onListAccount;
  final VoidCallback? onSyncWithApp;
  final VoidCallback? onDisconnectAccount;

  const _CloudOption({
    required this.connection,
    required this.account,
    required this.onConnectAccount,
    required this.onUploadAccount,
    required this.onListAccount,
    required this.onSyncWithApp,
    required this.onDisconnectAccount,
  });

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    final accountConnected = account != null;
    final icon = _providerIcon(connection.provider.id);
    final color = _providerColor(connection.provider.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accountConnected
              ? const Color(0xFFFFBF00).withValues(alpha: .35)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.provider.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  accountConnected
                      ? 'Account: ${account.accountLabel}'
                      : _providerSubtitle(connection.provider),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accountConnected ? Colors.white60 : Colors.white38,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onConnectAccount != null)
                      ElevatedButton.icon(
                        onPressed: onConnectAccount,
                        icon: const Icon(Icons.account_circle_outlined),
                        label: Text(
                          accountConnected
                              ? 'Reconnect account'
                              : 'Connect account',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFBF00),
                          foregroundColor: Colors.black,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: onUploadAccount,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Upload script'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onListAccount,
                      icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: const Text('Synced scripts'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onSyncWithApp,
                      icon: const Icon(Icons.sync_alt_rounded, size: 18),
                      label: const Text('Sync with App'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDisconnectAccount,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Disconnect account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (accountConnected)
            const _StatusPill(
              label: 'ACCOUNT',
              color: Colors.lightBlueAccent,
              background: Colors.blue,
            ),
        ],
      ),
    );
  }

  String _providerSubtitle(CloudProviderDefinition provider) {
    if (provider.id == CloudConnectionStore.dropbox) {
      return '${provider.subtitle}. Dropbox App Folder apps appear under Apps; '
          'keep scripts in Apps/AutoTeleprompter. Root-level folders require '
          'a Full Dropbox app.';
    }
    return provider.subtitle;
  }

  IconData _providerIcon(String providerId) {
    return switch (providerId) {
      CloudConnectionStore.googleDrive => Icons.add_to_drive,
      CloudConnectionStore.dropbox => Icons.cloud_queue_rounded,
      _ => Icons.cloud_done_outlined,
    };
  }

  Color _providerColor(String providerId) {
    return switch (providerId) {
      CloudConnectionStore.googleDrive => const Color(0xFF4285F4),
      CloudConnectionStore.dropbox => const Color(0xFF1E88FF),
      _ => Colors.white70,
    };
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: background.withValues(alpha: .35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ManagedCloudCard extends StatelessWidget {
  const _ManagedCloudCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFFBF00).withValues(alpha: .18)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync_lock_rounded, color: Color(0xFFFFBF00), size: 28),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AutoTeleprompter Cloud',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Managed premium storage will use AutoTeleprompter account '
                  'identity and company cloud storage. It stays locked until '
                  'the account backend, billing, and legal flow are ready.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationCard extends StatelessWidget {
  final bool anyConnected;
  final bool premiumUnlocked;
  final bool cloudAccountsConnected;
  final bool autoSyncScripts;
  final bool syncDeletedScriptsFolder;
  final bool recordingAutoBackup;
  final ValueChanged<bool> onAutoSyncScriptsChanged;
  final ValueChanged<bool> onSyncDeletedScriptsFolderChanged;
  final ValueChanged<bool> onRecordingAutoBackupChanged;

  const _AutomationCard({
    required this.anyConnected,
    required this.premiumUnlocked,
    required this.cloudAccountsConnected,
    required this.autoSyncScripts,
    required this.syncDeletedScriptsFolder,
    required this.recordingAutoBackup,
    required this.onAutoSyncScriptsChanged,
    required this.onSyncDeletedScriptsFolderChanged,
    required this.onRecordingAutoBackupChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AutomationRow(
            title: 'Auto-sync on save',
            subtitle: !premiumUnlocked
                ? 'Connect a Pro account to use script auto-sync.'
                : anyConnected
                    ? 'Backs up changed scripts every 30 seconds and before reading modes.'
                    : 'Connect an account or choose a Local Backup folder first.',
            enabled: premiumUnlocked && anyConnected,
            value: autoSyncScripts,
            onChanged: onAutoSyncScriptsChanged,
          ),
          const Divider(color: Colors.white12),
          _AutomationRow(
            title: 'Sync deleted scripts folder',
            subtitle: !premiumUnlocked
                ? 'Connect a Pro account to sync deleted-script cleanup.'
                : anyConnected
                    ? 'When deleted backups are removed from the app, remove matching Deleted Scripts files from connected cloud accounts and the Local Backup folder.'
                    : 'Connect a cloud account or choose a Local Backup folder first.',
            enabled: premiumUnlocked && anyConnected,
            value: syncDeletedScriptsFolder,
            onChanged: onSyncDeletedScriptsFolderChanged,
          ),
          const Divider(color: Colors.white12),
          _AutomationRow(
            title: 'Upload recordings automatically',
            subtitle: !premiumUnlocked
                ? 'Connect a Pro account to upload recordings automatically.'
                : cloudAccountsConnected
                    ? 'Uploads completed MP4/WAV recordings to connected cloud accounts.'
                    : 'Connect Google Drive or Dropbox before uploading recordings.',
            enabled: premiumUnlocked && cloudAccountsConnected,
            value: recordingAutoBackup,
            onChanged: onRecordingAutoBackupChanged,
          ),
        ],
      ),
    );
  }
}

class _AutomationRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AutomationRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.sync_rounded,
        color: Colors.white54,
        size: 22,
      ),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white30, fontSize: 12),
      ),
      trailing: Switch.adaptive(
        value: enabled && value,
        onChanged: enabled ? onChanged : null,
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFFFFBF00);
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0x66FFBF00);
          }
          return null;
        }),
      ),
    );
  }
}
