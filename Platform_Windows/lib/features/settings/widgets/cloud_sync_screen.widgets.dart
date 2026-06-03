part of 'cloud_sync_screen.dart';

class _CloudScriptPayload {
  final String title;
  final String text;
  final String? sourcePath;
  final String? sourceType;
  final String identity;

  const _CloudScriptPayload({
    required this.title,
    required this.text,
    required this.sourcePath,
    required this.sourceType,
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
        'the selected provider account and its terms. Local Backup writes '
        'script files to one local folder chosen on this device. '
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

  const _CloudActionBar({
    required this.enabled,
    required this.syncing,
    required this.onSyncScripts,
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
        const Text(
          'Sync scripts updates all saved scripts in connected cloud accounts '
          'and the Local Backup folder. Upload script remains available for '
          'manual single-script upload on each connected provider.',
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _LocalBackupCard extends StatelessWidget {
  final CloudProviderConnection connection;
  final VoidCallback onChoose;
  final VoidCallback? onOpen;
  final VoidCallback? onForget;
  final VoidCallback? onUpload;
  final VoidCallback? onList;

  const _LocalBackupCard({
    required this.connection,
    required this.onChoose,
    required this.onOpen,
    required this.onForget,
    required this.onUpload,
    required this.onList,
  });

  @override
  Widget build(BuildContext context) {
    final connected = connection.isConnected;
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
                  connected
                      ? 'Folder: ${connection.folderPath}'
                      : 'Choose one local folder for free backup and provider '
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
                      onPressed: onChoose,
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
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onForget,
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Forget folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onUpload,
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('Upload script'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onList,
                      icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: const Text('Synced scripts'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (connected)
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

class _CloudOption extends StatelessWidget {
  final CloudProviderConnection connection;
  final CloudAccountInfo? account;
  final VoidCallback? onConnectAccount;
  final VoidCallback? onUploadAccount;
  final VoidCallback? onListAccount;
  final VoidCallback? onDisconnectAccount;

  const _CloudOption({
    required this.connection,
    required this.account,
    required this.onConnectAccount,
    required this.onUploadAccount,
    required this.onListAccount,
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
                      : connection.provider.subtitle,
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
  final bool cloudAccountsConnected;
  final bool autoSyncScripts;
  final bool recordingAutoBackup;
  final ValueChanged<bool> onAutoSyncScriptsChanged;
  final ValueChanged<bool> onRecordingAutoBackupChanged;

  const _AutomationCard({
    required this.anyConnected,
    required this.cloudAccountsConnected,
    required this.autoSyncScripts,
    required this.recordingAutoBackup,
    required this.onAutoSyncScriptsChanged,
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
            subtitle: anyConnected
                ? 'Backs up changed scripts every 30 seconds and before reading modes.'
                : 'Connect an account or choose a Local Backup folder first.',
            enabled: anyConnected,
            value: autoSyncScripts,
            onChanged: onAutoSyncScriptsChanged,
          ),
          const Divider(color: Colors.white12),
          _AutomationRow(
            title: 'Upload recordings automatically',
            subtitle: cloudAccountsConnected
                ? 'Uploads completed MP4/WAV recordings to connected cloud accounts.'
                : 'Connect Google Drive or Dropbox before uploading recordings.',
            enabled: cloudAccountsConnected,
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
        activeThumbColor: const Color(0xFFFFBF00),
        activeTrackColor: const Color(0x66FFBF00),
      ),
    );
  }
}
