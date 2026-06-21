import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_screen.dart';
import '../services/cloud_connection_store.dart';
import 'deleted_scripts_screen.dart';

class CloudSyncScreen extends ConsumerWidget {
  const CloudSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Text(
          'CLOUD MANAGEMENT',
          style: GoogleFonts.bebasNeue(
            letterSpacing: 2,
            fontSize: 24,
            color: const Color(0xFFFFBF00),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white70,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: auth.hasPremiumAccess
            ? const _CloudSyncOptions()
            : _CloudLockedState(
                backendUnavailable: auth.accountBackendEnabled &&
                    auth.backendStatus == 'notConfigured',
              ),
      ),
    );
  }
}

class _CloudLockedState extends StatelessWidget {
  final bool backendUnavailable;

  const _CloudLockedState({required this.backendUnavailable});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: Color(0xFFFFBF00),
            size: 42,
          ),
          const SizedBox(height: 16),
          const Text(
            'Cloud sync requires Pro access',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            backendUnavailable
                ? 'This build does not include account backend configuration.'
                : 'Sign in with a Pro account to connect storage providers.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: backendUnavailable
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudSyncOptions extends ConsumerStatefulWidget {
  const _CloudSyncOptions();

  @override
  ConsumerState<_CloudSyncOptions> createState() => _CloudSyncOptionsState();
}

class _CloudSyncOptionsState extends ConsumerState<_CloudSyncOptions> {
  final CloudConnectionStore _store = CloudConnectionStore();
  late Future<_CloudSyncState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = _loadState();
  }

  Future<_CloudSyncState> _loadState() async {
    final local = await _store.loadLocalBackupConnection();
    final providers = await _store.loadConnections();
    return _CloudSyncState(localBackup: local, providers: providers);
  }

  void _refresh() {
    setState(() => _stateFuture = _loadState());
  }

  Future<void> _chooseLocalBackup() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose Local Backup Folder',
    );
    if (!mounted || path == null) return;
    await _store.setLocalBackupPath(path);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local backup folder connected.')),
    );
  }

  Future<void> _disconnectLocalBackup() async {
    await _store.disconnectLocalBackup();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local backup folder disconnected.')),
    );
  }

  void _showMobileProviderPending(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label account sign-in is not available in this build.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CloudSyncState>(
      future: _stateFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sync Sources',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect storage for scripts and backups.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _CloudOption(
              label: CloudConnectionStore.localBackupProvider.label,
              subtitle: CloudConnectionStore.localBackupProvider.subtitle,
              icon: Icons.folder_copy_rounded,
              color: const Color(0xFFFFBF00),
              status: _statusText(data?.localBackup.folderPath),
              actionLabel:
                  data?.localBackup.isConnected == true ? 'Disconnect' : null,
              onTap: _chooseLocalBackup,
              onAction: data?.localBackup.isConnected == true
                  ? _disconnectLocalBackup
                  : null,
            ),
            _CloudOption(
              label: 'Deleted Scripts',
              subtitle: 'Restore or permanently remove local deleted backups',
              icon: Icons.restore_from_trash_outlined,
              color: Colors.redAccent,
              status: data?.localBackup.isConnected == true
                  ? 'Available for local backups'
                  : 'Connect Local Backup first',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeletedScriptsScreen()),
              ),
            ),
            for (final connection in data?.providers ??
                CloudConnectionStore.providers.map(
                  (provider) => CloudProviderConnection(
                    provider: provider,
                    folderPath: '',
                  ),
                ))
              _CloudOption(
                label: connection.provider.label,
                subtitle: connection.provider.subtitle,
                icon: connection.provider.id == CloudConnectionStore.dropbox
                    ? Icons.cloud_queue_rounded
                    : Icons.add_to_drive_rounded,
                color: Colors.blueAccent,
                status: _statusText(connection.folderPath),
                onTap: () => _showMobileProviderPending(
                  connection.provider.label,
                ),
              ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(
                  color: Color(0xFFFFBF00),
                  backgroundColor: Colors.white12,
                ),
              ),
          ],
        );
      },
    );
  }

  static String _statusText(String? path) {
    final clean = CloudConnectionStore.normalizePath(path);
    return clean.isEmpty ? 'Not connected' : clean;
  }
}

class _CloudOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String status;
  final VoidCallback onTap;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CloudOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.status,
    required this.onTap,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final connected = status != 'Not connected';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? const Color(0xFFFFBF00).withValues(alpha: .28)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 4),
              Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: connected ? const Color(0xFFFFBF00) : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        trailing: actionLabel == null
            ? const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white24,
                size: 16,
              )
            : TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
      ),
    );
  }
}

class _CloudSyncState {
  final CloudProviderConnection localBackup;
  final List<CloudProviderConnection> providers;

  const _CloudSyncState({
    required this.localBackup,
    required this.providers,
  });
}
