part of 'cloud_sync_screen.dart';

class _CloudOption extends StatelessWidget {
  final CloudProviderConnection connection;
  final CloudAccountInfo? account;
  final CloudConnectionStatus? connectionStatus;
  final VoidCallback? onConnectAccount;
  final VoidCallback? onCheckConnection;
  final bool signInBusy;
  final bool checking;
  final VoidCallback? onUploadAccount;
  final VoidCallback? onListAccount;
  final VoidCallback? onSyncWithApp;
  final VoidCallback? onDisconnectAccount;

  const _CloudOption({
    required this.connection,
    required this.account,
    this.connectionStatus,
    required this.onConnectAccount,
    required this.onCheckConnection,
    this.signInBusy = false,
    this.checking = false,
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
          color:
              accountConnected
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
                if (accountConnected) ...[
                  const SizedBox(height: 6),
                  Text(
                    connectionStatus?.message ??
                        'Saved connection — checking session',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    CloudAccountConnectionActions(
                      connected: accountConnected,
                      signInBusy: signInBusy,
                      checking: checking,
                      onConnect: onConnectAccount,
                      onCheck: onCheckConnection,
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
