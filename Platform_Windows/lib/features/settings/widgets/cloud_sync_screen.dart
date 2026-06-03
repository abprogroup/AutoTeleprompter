import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/security/secure_script_store.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/providers/script_provider.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_app_folder_sync_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/cloud_oauth_service.dart';
import '../services/local_backup_service.dart';

part 'cloud_sync_screen.actions.dart';
part 'cloud_sync_screen.widgets.dart';

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
  CloudProviderConnection? _localBackup;
  bool _loading = true;
  bool _syncingScripts = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final connections = await _store.loadConnections();
    final localBackup = await _store.loadLocalBackupConnection();
    final accounts = await _oauth.loadAccounts();
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _localBackup = localBackup;
      _accounts = accounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final anyConnected =
        (_localBackup?.isConnected ?? false) || _accounts.isNotEmpty;
    final body = _buildCloudManagementBody(anyConnected, settings);

    if (widget.embedded) return body;

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
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white70,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }

  Widget _buildCloudManagementBody(bool anyConnected, AppSettings settings) {
    final localBackup = _localBackup ??
        const CloudProviderConnection(
          provider: CloudConnectionStore.localBackupProvider,
          folderPath: '',
        );
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
            'Connect Google Drive or Dropbox accounts for online app-folder '
            'sync. Use Local Backup once for free local folder backup, including '
            'folders already synced by desktop cloud apps.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _CloudDisclosureNote(),
          const SizedBox(height: 16),
          _CloudActionBar(
            enabled: anyConnected && !_syncingScripts,
            syncing: _syncingScripts,
            onSyncScripts: _syncAllScripts,
          ),
          const SizedBox(height: 32),
          const _SectionLabel('LOCAL BACKUP'),
          const SizedBox(height: 12),
          _LocalBackupCard(
            connection: localBackup,
            onChoose: _chooseLocalBackupFolder,
            onOpen: localBackup.isConnected
                ? () => _openFolder(localBackup.folderPath)
                : null,
            onForget: localBackup.isConnected ? _disconnectLocalBackup : null,
            onUpload:
                localBackup.isConnected ? _uploadLocalBackupScripts : null,
            onList: localBackup.isConnected ? _showLocalBackupScripts : null,
          ),
          const SizedBox(height: 24),
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
                onConnectAccount:
                    _providerSupportsAccount(connection.provider.id)
                        ? () => _connectProviderAccount(connection.provider)
                        : null,
                onUploadAccount: _accounts.containsKey(connection.provider.id)
                    ? () => _uploadSelectedScripts(connection.provider.id)
                    : null,
                onListAccount: _accounts.containsKey(connection.provider.id)
                    ? () => _showSyncedScripts(connection.provider)
                    : null,
                onDisconnectAccount: _accounts
                        .containsKey(connection.provider.id)
                    ? () => _disconnectProviderAccount(connection.provider.id)
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
            cloudAccountsConnected: _accounts.isNotEmpty,
            autoSyncScripts: settings.cloudAutoSyncOnSave,
            recordingAutoBackup: settings.recordingAutoBackup,
            onAutoSyncScriptsChanged: _setAutoSyncScripts,
            onRecordingAutoBackupChanged: _setRecordingAutoBackup,
          ),
        ],
      ),
    );
  }

  bool _providerSupportsAccount(String providerId) {
    return providerId == CloudConnectionStore.googleDrive ||
        providerId == CloudConnectionStore.dropbox;
  }

  Future<void> _chooseLocalBackupFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose local backup folder',
    );
    if (folder == null) return;
    final directory = Directory(folder);
    if (!await directory.exists()) {
      _showSnack('Selected folder does not exist.');
      return;
    }
    await _store.setLocalBackupPath(folder);
    await _loadConnections();
    _showSnack('Local backup folder linked.');
  }

  Future<void> _disconnectLocalBackup() async {
    await _store.disconnectLocalBackup();
    await _loadConnections();
    _showSnack('Local backup folder forgotten.');
  }

  void _setSyncingScripts(bool value) {
    if (!mounted) return;
    setState(() => _syncingScripts = value);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _shortError(Object error) {
    final compact = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 220) return compact;
    return '${compact.substring(0, 220)}...';
  }
}
