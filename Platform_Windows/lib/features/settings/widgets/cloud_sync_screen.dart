import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/providers/script_provider.dart';
import '../services/cloud_app_folder_sync_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/cloud_oauth_service.dart';

class CloudSyncScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const CloudSyncScreen({
    super.key,
    this.embedded = false,
  });

  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  final _store = CloudConnectionStore();
  final _oauth = CloudOAuthService();
  late final _sync = CloudAppFolderSyncService(oauth: _oauth);
  List<CloudProviderConnection> _connections = const [];
  Map<String, CloudAccountInfo> _accounts = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final connections = await _store.loadConnections();
    final accounts = await _oauth.loadAccounts();
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _accounts = accounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final anyCloudConnection =
        _connections.any((item) => item.isConnected) || _accounts.isNotEmpty;
    final body = _buildCloudManagementBody(anyCloudConnection);

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Text(
          'Cloud Management',
          style: GoogleFonts.bebasNeue(
            letterSpacing: 2,
            fontSize: 24,
            color: const Color(0xFFFFBF00),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }

  Widget _buildCloudManagementBody(bool anyConnected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cloud Connections',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect Google Drive or Dropbox accounts when app credentials '
            'are configured, or link folders already synced by iCloud, Google '
            'Drive, or Dropbox. Windows iCloud uses the local iCloud Drive '
            'folder bridge.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _CloudDisclosureNote(),
          const SizedBox(height: 32),
          const _SectionLabel('PERSONAL CLOUD STORAGE'),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
              ),
            )
          else
            for (final connection in _connections)
              _CloudOption(
                connection: connection,
                account: _accounts[connection.provider.id],
                onConnect: () => _chooseFolder(connection.provider.id),
                onConnectAccount:
                    connection.provider.id == CloudConnectionStore.icloud
                        ? null
                        : () => _connectProviderAccount(connection.provider),
                onUploadAccount: _accounts.containsKey(connection.provider.id)
                    ? () => _uploadCurrentScript(connection.provider.id)
                    : null,
                onListAccount: _accounts.containsKey(connection.provider.id)
                    ? () => _showSyncedScripts(connection.provider)
                    : null,
                onDisconnectAccount: _accounts
                        .containsKey(connection.provider.id)
                    ? () => _disconnectProviderAccount(connection.provider.id)
                    : null,
                onDisconnect: connection.isConnected
                    ? () => _disconnect(connection.provider.id)
                    : null,
                onOpen: connection.isConnected
                    ? () => _openFolder(connection.folderPath)
                    : null,
              ),
          const SizedBox(height: 16),
          const _SectionLabel('MANAGED CLOUD'),
          const SizedBox(height: 6),
          const Text(
            'Waiting for future development. This will use AutoTeleprompter '
            'accounts and company-managed storage, not personal providers.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          const _ManagedCloudCard(),
          const SizedBox(height: 32),
          const _SectionLabel('AUTOMATION'),
          const SizedBox(height: 8),
          _AutomationCard(
            anyConnected: anyConnected,
            onActivate: _showAutomationPlanned,
          ),
        ],
      ),
    );
  }

  Future<void> _chooseFolder(String providerId) async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose local synced cloud folder',
    );
    if (folder == null) return;
    final directory = Directory(folder);
    if (!await directory.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected folder does not exist.')),
      );
      return;
    }
    await _store.setFolderPath(providerId, folder);
    await _loadConnections();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Local synced folder linked.')),
    );
  }

  Future<void> _disconnect(String providerId) async {
    await _store.disconnect(providerId);
    await _loadConnections();
  }

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else {
        await Process.run('open', [path]);
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.openFolder',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the cloud folder.')),
      );
    }
  }

  Future<void> _connectProviderAccount(CloudProviderDefinition provider) async {
    final result = await _oauth.connect(provider);
    await _loadConnections();
    if (!mounted) return;
    if (result.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(
          result.missingCredentials
              ? '${provider.label} needs app credentials'
              : '${provider.label} account connection',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          result.message,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _chooseFolder(provider.id);
            },
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose local folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectProviderAccount(String providerId) async {
    await _oauth.disconnect(providerId);
    await _loadConnections();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cloud account disconnected.')),
    );
  }

  Future<void> _uploadCurrentScript(String providerId) async {
    final script = ref.read(scriptProvider);
    if (script == null || script.rawText.trim().isEmpty) {
      _showSnack('Open a script before uploading to cloud.');
      return;
    }
    try {
      final result = await _sync.uploadScript(
        providerId: providerId,
        title: script.title,
        text: script.rawText,
      );
      _showSnack(result.message);
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.uploadCurrentScript',
      );
      _showSnack('Cloud upload failed. Check the account connection.');
    }
  }

  Future<void> _showSyncedScripts(CloudProviderDefinition provider) async {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: Text(
          '${provider.label} scripts',
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<CloudSyncedFile>>(
            future: _sync.listScripts(provider.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFFBF00),
                    ),
                  ),
                );
              }
              final files = snapshot.data ?? const <CloudSyncedFile>[];
              if (files.isEmpty) {
                return const Text(
                  'No scripts are synced in the AutoTeleprompter app folder yet.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        file.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        file.modifiedAtIso ?? 'Cloud script',
                        style: const TextStyle(color: Colors.white38),
                      ),
                      trailing: TextButton(
                        onPressed: () => _downloadSyncedScript(file),
                        child: const Text('Download'),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSyncedScript(CloudSyncedFile file) async {
    try {
      final text = await _sync.downloadScript(
        providerId: file.providerId,
        fileId: file.id,
      );
      if (text == null || text.isEmpty) {
        _showSnack('Cloud download failed.');
        return;
      }
      ref.read(scriptProvider.notifier).loadText(
            text,
            title: file.name,
            sourceType: 'CLOUD',
            sessionId: 'cloud_${DateTime.now().microsecondsSinceEpoch}',
          );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack('Downloaded ${file.name}.');
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.downloadSyncedScript',
      );
      _showSnack('Cloud download failed. Check the account connection.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAutomationPlanned() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        title: const Text(
          'Automatic background sync is unavailable',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Manual account sync and local synced folders are available now. '
          'Turning on automatic script sync or recording upload still needs '
          'the background sync scheduler and conflict-safe file handling.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
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
        'the selected provider account and its terms. Local folder links use '
        'folders already synced on this device. AutoTeleprompter Cloud is a '
        'separate managed service planned for a later account release.',
        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _CloudOption extends StatelessWidget {
  final CloudProviderConnection connection;
  final CloudAccountInfo? account;
  final VoidCallback onConnect;
  final VoidCallback? onConnectAccount;
  final VoidCallback? onUploadAccount;
  final VoidCallback? onListAccount;
  final VoidCallback? onDisconnectAccount;
  final VoidCallback? onDisconnect;
  final VoidCallback? onOpen;

  const _CloudOption({
    required this.connection,
    required this.account,
    required this.onConnect,
    required this.onConnectAccount,
    required this.onUploadAccount,
    required this.onListAccount,
    required this.onDisconnectAccount,
    required this.onDisconnect,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final connected = connection.isConnected;
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
          color: connected
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
                  _subtitleText(connection, account),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: connected || accountConnected
                        ? Colors.white60
                        : Colors.white38,
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
                      onPressed: onConnect,
                      icon: Icon(connected
                          ? Icons.drive_folder_upload_outlined
                          : Icons.folder_open_outlined),
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
                      onPressed: onDisconnect,
                      icon: const Icon(Icons.link_off_rounded, size: 18),
                      label: const Text('Forget folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onConnectAccount,
                      icon: const Icon(
                        Icons.account_circle_outlined,
                        size: 18,
                      ),
                      label: Text(
                        accountConnected
                            ? 'Reconnect account'
                            : onConnectAccount == null
                                ? 'Local bridge only'
                                : 'Connect account',
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
          if (connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.green.withValues(alpha: .35)),
              ),
              child: const Text(
                'FOLDER LINKED',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (!connected && accountConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.blue.withValues(alpha: .35)),
              ),
              child: const Text(
                'ACCOUNT',
                style: TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitleText(
    CloudProviderConnection connection,
    CloudAccountInfo? account,
  ) {
    final parts = <String>[];
    if (account != null) parts.add('Account: ${account.accountLabel}');
    if (connection.isConnected) {
      parts.add('Folder: ${connection.folderPath}');
    }
    return parts.isEmpty ? connection.provider.subtitle : parts.join('  |  ');
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
  final VoidCallback onActivate;

  const _AutomationCard({
    required this.anyConnected,
    required this.onActivate,
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
                ? 'Use manual account sync or the linked folder for now. '
                    'Background copy/sync is unavailable.'
                : 'Connect an account or choose a local synced folder first. '
                    'Background copy/sync is unavailable.',
            onActivate: onActivate,
          ),
          const Divider(color: Colors.white12),
          _AutomationRow(
            title: 'Upload recordings automatically',
            subtitle: anyConnected
                ? 'Use manual account sync or Open folder after recording. '
                    'Background recording copy is unavailable.'
                : 'Connect an account or choose a local synced folder first. '
                    'Background recording copy is unavailable.',
            onActivate: onActivate,
          ),
        ],
      ),
    );
  }
}

class _AutomationRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onActivate;

  const _AutomationRow({
    required this.title,
    required this.subtitle,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.lock_clock_outlined,
        color: Colors.white38,
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
      trailing: TextButton(
        onPressed: onActivate,
        child: const Text('Details'),
      ),
    );
  }
}
