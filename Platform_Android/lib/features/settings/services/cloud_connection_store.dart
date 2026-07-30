import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloudProviderConnection {
  final String folderPath;

  const CloudProviderConnection({required this.folderPath});

  bool get isConnected => folderPath.isNotEmpty;
}

class CloudProviderDefinition {
  final String id;
  final String label;
  final String subtitle;

  const CloudProviderDefinition({
    required this.id,
    required this.label,
    required this.subtitle,
  });
}

/// Windows lets the user pick any folder on disk for Local Backup. Android's
/// scoped storage (API 29+) has no equivalent: a Storage Access Framework
/// folder pick returns a content:// tree URI that dart:io cannot read or
/// write through, which would require new native DocumentFile code to
/// support. Local Backup on Android instead lives in a fixed, app-private
/// external-storage folder that the user only toggles on/off and never
/// relocates - matches `android_parity_gaps.md` #4's documented adaptation.
class CloudConnectionStore {
  static const String deletedScriptsFolderName = 'Deleted Scripts';
  static const String backupScriptsFolderName = 'Backup Scripts';
  static const _localBackupEnabledKey = 'localBackup.enabled';

  // Personal Cloud Storage (real OAuth account sync - `cloud_oauth_service.dart`).
  // Distinct from Local Backup above, which is a fixed app-private folder,
  // not an account connection. Matches Windows' `CloudConnectionStore`
  // provider-definition shape; Android never carried Windows' folder-path-
  // per-provider-id scheme since Local Backup already took a simpler,
  // scoped-storage-appropriate path (see the class doc above).
  static const String googleDrive = 'google_drive';
  static const String dropbox = 'dropbox';

  static const providers = [
    CloudProviderDefinition(
      id: googleDrive,
      label: 'Google Drive',
      subtitle: 'Connect your Google Drive account for app-folder sync',
    ),
    CloudProviderDefinition(
      id: dropbox,
      label: 'Dropbox',
      subtitle: 'Connect Dropbox account sync for AutoTeleprompter scripts',
    ),
  ];

  Future<bool> isLocalBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_localBackupEnabledKey) ?? false;
  }

  Future<void> setLocalBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localBackupEnabledKey, enabled);
  }

  Future<CloudProviderConnection> loadLocalBackupConnection() async {
    if (!await isLocalBackupEnabled()) {
      return const CloudProviderConnection(folderPath: '');
    }
    final root = await _appExternalRoot();
    if (root == null) return const CloudProviderConnection(folderPath: '');
    return CloudProviderConnection(
      folderPath: joinPath(root.path, backupScriptsFolderName),
    );
  }

  Future<String> resolveDeletedScriptsFolderPath() async {
    if (!await isLocalBackupEnabled()) return '';
    final root = await _appExternalRoot();
    if (root == null) return '';
    return joinPath(root.path, deletedScriptsFolderName);
  }

  Future<Directory?> _appExternalRoot() => getExternalStorageDirectory();

  static String joinPath(String left, String right) {
    if (left.isEmpty) return right;
    return left.endsWith(Platform.pathSeparator)
        ? '$left$right'
        : '$left${Platform.pathSeparator}$right';
  }
}
