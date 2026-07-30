import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/security/secure_script_store.dart';
import '../../auth/providers/auth_provider.dart';
import '../../feedback/services/lightweight_diagnostics.dart';
import '../../script/models/script.dart';
import '../../script/providers/script_provider.dart';
import '../../script/services/script_bookmark_service.dart';
import '../../script/services/script_project_codec.dart';
import '../services/settings_error_sanitizer.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_app_folder_sync_service.dart';
import '../services/cloud_connection_store.dart';
import '../services/cloud_oauth_service.dart';
import '../services/local_backup_service.dart';
import '../services/deleted_scripts_service.dart';

part 'cloud_sync_screen.payloads.dart';
part 'cloud_sync_screen.synced_scripts_dialog.dart';
part 'cloud_sync_screen.deleted_actions.dart';
part 'cloud_sync_screen.managed_sync.dart';

/// Ported from Windows'/iOS' `cloud_sync_screen.dart` + part files, scoped to
/// just the "Personal Cloud Storage" section (real OAuth account sync to
/// Google Drive/Dropbox). Windows' "Local Backup" folder-picker section is
/// deliberately NOT duplicated here - Android already has its own adapted
/// version (`app_settings_screen.local_backup.dart`, fixed app-private
/// folder, no picker - see `android_parity_gaps.md` #2). Windows' "Managed
/// Cloud" section is an unimplemented placeholder there too ("Waiting for
/// future development"), so nothing to port.
///
/// "Sync All Scripts" bulk reconciliation (`cloud_sync_screen.managed_sync.dart`/
/// `.deleted_actions.dart`) was ported 2026-07-30, adapted from iOS (not
/// Windows) since iOS is the actual same-form-factor mobile precedent and
/// ships this exact feature on a phone - the original "too risky for mobile"
/// deferral reasoning didn't hold up once iOS's shipped version was checked.
/// "Sync with App" folder-reconciliation is still not ported - it
/// reconciles against Local Backup's folder, which Android's separate
/// `app_settings_screen.local_backup.dart` structure doesn't expose in a way
/// this screen can read the same way Windows/iOS do. See `cloud_sync_mvp.md`.
class CloudSyncScreen extends ConsumerStatefulWidget {
  final bool embedded;

  const CloudSyncScreen({super.key, this.embedded = false});

  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  final _oauth = CloudOAuthService();
  late final _sync = CloudAppFolderSyncService(oauth: _oauth);

  Map<String, CloudAccountInfo> _accounts = const {};
  bool _loading = true;
  bool _syncingScripts = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final accounts = await _oauth.loadAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final premiumUnlocked = auth.hasPremiumAccess;
    final body = _buildCloudManagementBody(premiumUnlocked);

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Text(
          'Cloud Sync',
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

  Widget _buildCloudManagementBody(bool premiumUnlocked) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Personal Cloud Storage',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect a Google Drive or Dropbox account to upload scripts to '
            'a private AutoTeleprompter app folder and sync them back down '
            'on any device signed into the same account.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _CloudDisclosureNote(),
          const SizedBox(height: 16),
          if (!_loading && _accounts.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (premiumUnlocked && !_syncingScripts)
                    ? _syncAllScripts
                    : null,
                icon: _syncingScripts
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFFBF00),
                        ),
                      )
                    : const Icon(Icons.sync_rounded),
                label: const Text('Sync All Scripts'),
              ),
            ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
              ),
            )
          else
            for (final provider in CloudConnectionStore.providers)
              _CloudOption(
                provider: provider,
                account: _accounts[provider.id],
                onConnectAccount: premiumUnlocked
                    ? () => _connectProviderAccount(provider)
                    : null,
                onUploadAccount: premiumUnlocked &&
                        _accounts.containsKey(provider.id) &&
                        !_syncingScripts
                    ? () => _uploadSelectedScripts(provider.id)
                    : null,
                onListAccount:
                    premiumUnlocked && _accounts.containsKey(provider.id)
                        ? () => _showSyncedScripts(provider)
                        : null,
                onDisconnectAccount:
                    premiumUnlocked && _accounts.containsKey(provider.id)
                        ? () => _disconnectProviderAccount(provider.id)
                        : null,
              ),
        ],
      ),
    );
  }

  Future<void> _connectProviderAccount(CloudProviderDefinition provider) async {
    final result = await _oauth.connect(provider);
    await _loadConnections();
    if (!mounted) return;
    if (result.connected) {
      _showSnack(result.message);
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
        ],
      ),
    );
  }

  Future<void> _disconnectProviderAccount(String providerId) async {
    await _oauth.disconnect(providerId);
    await _loadConnections();
    _showSnack('Cloud account disconnected.');
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
    final compact = sanitizeSettingsErrorForUser(error)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (compact.length <= 220) return compact;
    return '${compact.substring(0, 220)}...';
  }

  String _providerLabel(String providerId) {
    return switch (providerId) {
      CloudConnectionStore.googleDrive => 'Google Drive',
      CloudConnectionStore.dropbox => 'Dropbox',
      _ => providerId,
    };
  }

  bool _providerSupportsAccount(String providerId) {
    return providerId == CloudConnectionStore.googleDrive ||
        providerId == CloudConnectionStore.dropbox;
  }

  Future<void> _syncAllScripts() async {
    if (_syncingScripts) return;
    final providers = [
      for (final provider in CloudConnectionStore.providers)
        if (_accounts.containsKey(provider.id) &&
            _providerSupportsAccount(provider.id))
          provider.id,
    ];
    if (providers.isEmpty) {
      _showSnack('Connect a cloud account first.');
      return;
    }

    final availableScripts = await _scriptPayloadsForSync();
    final deletedScripts =
        await DeletedScriptsService().listLocalDeletedScripts();
    final cloudOnlyScripts = await _cloudOnlyScriptsForManagedSync(
      providerIds: providers,
      localScripts: availableScripts,
    );
    final cloudDeletedScripts = await _cloudDeletedScriptsForManagedSync(
      providerIds: providers,
    );
    if (availableScripts.isEmpty &&
        deletedScripts.isEmpty &&
        cloudOnlyScripts.isEmpty &&
        cloudDeletedScripts.isEmpty) {
      _showSnack(
          'No saved, deleted, cloud-only, or cloud-deleted scripts are available.');
      return;
    }
    final selection = await _chooseManagedSyncAction(
      savedScripts: availableScripts,
      deletedScripts: deletedScripts,
      cloudOnlyScripts: cloudOnlyScripts,
      cloudDeletedScripts: cloudDeletedScripts,
    );
    if (selection == null || selection.isEmpty) return;
    final scripts = selection.savedScripts;
    final selectedDeletedScripts = selection.deletedScripts;
    final cloudOnlyToDelete = selection.cloudOnlyScripts;
    final cloudDeletedToRestore = selection.cloudDeletedScripts;

    _setSyncingScripts(true);
    _showSnack(
      'Syncing ${scripts.length} saved scripts and '
      '${selectedDeletedScripts.length} deleted backups...',
    );
    final cloudOkByProvider = {
      for (final providerId in providers) providerId: 0,
    };
    final cloudFailedByProvider = {
      for (final providerId in providers) providerId: 0,
    };
    final deletedOkByProvider = {
      for (final providerId in providers) providerId: 0,
    };
    final failures = <String>[];
    try {
      for (final script in scripts) {
        for (final providerId in providers) {
          final result = await _uploadScriptAndMetadata(
            providerId: providerId,
            script: script,
          );
          if (result.ok) {
            cloudOkByProvider[providerId] =
                (cloudOkByProvider[providerId] ?? 0) + 1;
          } else {
            cloudFailedByProvider[providerId] =
                (cloudFailedByProvider[providerId] ?? 0) + 1;
            failures.add('${_providerLabel(providerId)}: ${result.message}');
          }
        }
      }
      for (final providerId in providers) {
        final deletedOk = await _syncDeletedScriptsForProvider(
          providerId: providerId,
          deletedScripts: selectedDeletedScripts,
          failures: failures,
        );
        deletedOkByProvider[providerId] = deletedOk;
      }
      var cloudOnlyMoved = 0;
      for (final script in cloudOnlyToDelete) {
        final result = await _sync.moveSyncedScriptToDeleted(
          providerId: script.providerId,
          primaryFileName: script.fileName,
        );
        if (result.ok) {
          cloudOnlyMoved++;
        } else {
          failures.add('${script.providerLabel}: ${result.message}');
        }
      }
      var cloudDeletedRestored = 0;
      for (final script in cloudDeletedToRestore) {
        final result = await _sync.restoreDeletedScript(
          providerId: script.providerId,
          deletedFileName: script.fileName,
          activeFileName: script.activeFileName,
        );
        if (result.ok) {
          cloudDeletedRestored++;
        } else {
          failures.add('${script.providerLabel}: ${result.message}');
        }
      }

      final targetText = [
        for (final providerId in providers)
          '${_providerLabel(providerId)}: '
              '${cloudOkByProvider[providerId] ?? 0} saved, '
              '${deletedOkByProvider[providerId] ?? 0} deleted',
      ].join(', ');
      final cloudFailed = cloudFailedByProvider.values
          .fold<int>(0, (sum, count) => sum + count);
      if (failures.isEmpty && cloudFailed == 0) {
        _showSnack(
          'Synced ${scripts.length} scripts and '
          '${selectedDeletedScripts.length} deleted backups'
          '${cloudOnlyMoved > 0 ? ', moved $cloudOnlyMoved cloud-only files' : ''} '
          '${cloudDeletedRestored > 0 ? ', restored $cloudDeletedRestored cloud-deleted files' : ''} '
          '($targetText).',
        );
      } else {
        _showSnack(
          'Sync finished ($targetText) with ${failures.length} failures. '
          '${failures.first}',
        );
      }
    } catch (error, stack) {
      LightweightDiagnostics.instance.recordError(
        error,
        stack,
        source: 'cloud.syncAllScripts',
      );
      _showSnack('Sync failed: ${_shortError(error)}');
    } finally {
      _setSyncingScripts(false);
    }
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
        'bookmarks, history, and script settings, inside a private '
        'AutoTeleprompter app folder in your account.',
        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _CloudOption extends StatelessWidget {
  final CloudProviderDefinition provider;
  final CloudAccountInfo? account;
  final VoidCallback? onConnectAccount;
  final VoidCallback? onUploadAccount;
  final VoidCallback? onListAccount;
  final VoidCallback? onDisconnectAccount;

  const _CloudOption({
    required this.provider,
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
    final icon = _providerIcon(provider.id);
    final color = _providerColor(provider.id);
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
                  provider.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  accountConnected
                      ? 'Account: ${account.accountLabel}'
                      : _providerSubtitle(provider),
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

  String _providerSubtitle(CloudProviderDefinition provider) {
    if (provider.id == CloudConnectionStore.dropbox) {
      return '${provider.subtitle}. Dropbox App Folder apps appear under '
          'Apps/AutoTeleprompter in your Dropbox.';
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
