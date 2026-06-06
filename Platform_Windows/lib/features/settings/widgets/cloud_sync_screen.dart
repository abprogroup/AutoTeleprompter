import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/security/secure_script_store.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../auth/providers/auth_provider.dart';
import '../../script/models/script.dart';
import '../../script/providers/script_provider.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/script_project_codec.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_app_folder_sync_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/cloud_oauth_service.dart';
import '../services/deleted_scripts_service.dart';
import '../services/local_backup_service.dart';

part 'cloud_sync_screen.actions.dart';
part 'cloud_sync_screen.deleted_actions.dart';
part 'cloud_sync_screen.folder_moves.dart';
part 'cloud_sync_screen.local_backup_dialogs.dart';
part 'cloud_sync_screen.managed_sync.dart';
part 'cloud_sync_screen.payloads.dart';
part 'cloud_sync_screen.sync_with_app.dart';
part 'cloud_sync_screen.synced_scripts_dialog.dart';
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
  bool _deletedFolderOverride = false;
  String _deletedFolderPath = '';
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
    final deletedFolderOverride =
        await _store.loadDeletedScriptsCustomFolderEnabled();
    final deletedFolderPath = await _store.loadDeletedScriptsCustomFolderPath();
    final accounts = await _oauth.loadAccounts();
    if (!mounted) return;
    setState(() {
      _connections = connections;
      _localBackup = localBackup;
      _deletedFolderOverride = deletedFolderOverride;
      _deletedFolderPath = deletedFolderPath;
      _accounts = accounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final premiumUnlocked = auth.hasPremiumAccess;
    final anyConnected =
        (_localBackup?.isConnected ?? false) || _accounts.isNotEmpty;
    final body = _buildCloudManagementBody(
      anyConnected,
      settings,
      premiumUnlocked,
    );

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

  Widget _buildCloudManagementBody(
    bool anyConnected,
    AppSettings settings,
    bool premiumUnlocked,
  ) {
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
            'Connect Google Drive or Dropbox accounts for online '
            'sync. Use Local Backup for Pro local folder backup, including '
            'folders already synced by desktop cloud apps.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _CloudDisclosureNote(),
          const SizedBox(height: 16),
          _CloudActionBar(
            enabled: premiumUnlocked && anyConnected && !_syncingScripts,
            syncing: _syncingScripts,
            onSyncScripts: _syncAllScripts,
          ),
          const SizedBox(height: 32),
          const _SectionLabel('LOCAL BACKUP'),
          const SizedBox(height: 12),
          _LocalBackupCard(
            connection: localBackup,
            enabled: premiumUnlocked,
            onChoose: _chooseLocalBackupFolder,
            onOpen: localBackup.isConnected
                ? () => _openFolder(localBackup.folderPath)
                : null,
            onForget: localBackup.isConnected ? _disconnectLocalBackup : null,
            onUpload:
                localBackup.isConnected ? _uploadLocalBackupScripts : null,
            onList: localBackup.isConnected ? _showLocalBackupScripts : null,
            onSyncWithApp:
                localBackup.isConnected ? _syncLocalBackupWithApp : null,
          ),
          const SizedBox(height: 12),
          _DeletedScriptsFolderCard(
            enabled: premiumUnlocked,
            useCustomFolder: _deletedFolderOverride,
            folderPath: _resolvedDeletedFolderLabel(localBackup),
            onToggleCustomFolder: _setDeletedFolderOverride,
            onChoose: _chooseDeletedScriptsFolder,
            onOpen: _deletedFolderPath.trim().isNotEmpty
                ? () => _openFolder(_deletedFolderPath)
                : null,
            onForget: _deletedFolderPath.trim().isNotEmpty
                ? _forgetDeletedScriptsFolder
                : null,
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
                onConnectAccount: premiumUnlocked &&
                        _providerSupportsAccount(connection.provider.id)
                    ? () => _connectProviderAccount(connection.provider)
                    : null,
                onUploadAccount: premiumUnlocked &&
                        _accounts.containsKey(connection.provider.id)
                    ? () => _uploadSelectedScripts(connection.provider.id)
                    : null,
                onListAccount: premiumUnlocked &&
                        _accounts.containsKey(connection.provider.id)
                    ? () => _showSyncedScripts(connection.provider)
                    : null,
                onSyncWithApp: premiumUnlocked &&
                        _accounts.containsKey(connection.provider.id)
                    ? () => _syncProviderWithApp(connection.provider.id)
                    : null,
                onDisconnectAccount: premiumUnlocked &&
                        _accounts.containsKey(connection.provider.id)
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
            premiumUnlocked: premiumUnlocked,
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
    final oldFolder = _localBackup?.folderPath.trim() ?? '';
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose local backup folder',
    );
    if (folder == null) return;
    final directory = Directory(folder);
    if (!await directory.exists()) {
      _showSnack('Selected folder does not exist.');
      return;
    }
    await _maybeMoveExistingFolderContents(
      oldPath: oldFolder,
      newPath: folder,
      title: 'Move existing Local Backup files?',
      message:
          'Move existing backed-up scripts and deleted-script folders to the '
          'new Local Backup folder?',
    );
    await _store.setLocalBackupPath(folder);
    await _loadConnections();
    _showSnack('Local backup folder linked.');
  }

  Future<void> _disconnectLocalBackup() async {
    await _store.disconnectLocalBackup();
    await _loadConnections();
    _showSnack('Local backup folder forgotten.');
  }

  String _resolvedDeletedFolderLabel(CloudProviderConnection localBackup) {
    if (_deletedFolderOverride) {
      return _deletedFolderPath.trim();
    }
    final localPath = localBackup.folderPath.trim();
    if (localPath.isEmpty) return '';
    return CloudConnectionStore.joinPath(
      localPath,
      CloudConnectionStore.deletedScriptsFolderName,
    );
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
    var compact = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    compact = compact.replaceFirst(RegExp(r'^(Bad state|Exception):\s*'), '');
    if (compact.length <= 220) return compact;
    return '${compact.substring(0, 220)}...';
  }
}
