import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

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

class CloudProviderConnection {
  final CloudProviderDefinition provider;
  final String folderPath;

  const CloudProviderConnection({
    required this.provider,
    required this.folderPath,
  });

  bool get isConnected => folderPath.isNotEmpty;
}

class CloudConnectionStore {
  static const String localBackup = 'local_backup';
  static const String icloud = 'icloud';
  static const String googleDrive = 'google_drive';
  static const String dropbox = 'dropbox';
  static const String deletedScriptsFolderName = 'Deleted Scripts';

  static const localBackupProvider = CloudProviderDefinition(
    id: localBackup,
    label: 'Local Backup',
    subtitle: 'Choose one local folder for free local script backup',
  );

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

  static String _keyFor(String providerId) => 'cloudFolder.$providerId';
  static const _deletedScriptsCustomFolderEnabledKey =
      'deletedScripts.customFolder.enabled';
  static const _deletedScriptsCustomFolderPathKey =
      'deletedScripts.customFolder.path';

  Future<List<CloudProviderConnection>> loadConnections() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final provider in providers)
        CloudProviderConnection(
          provider: provider,
          folderPath: normalizePath(prefs.getString(_keyFor(provider.id))),
        ),
    ];
  }

  Future<CloudProviderConnection> loadLocalBackupConnection() async {
    final prefs = await SharedPreferences.getInstance();
    var folderPath = normalizePath(prefs.getString(_keyFor(localBackup)));
    if (folderPath.isEmpty) {
      for (final legacyId in [icloud, googleDrive, dropbox]) {
        folderPath = normalizePath(prefs.getString(_keyFor(legacyId)));
        if (folderPath.isNotEmpty) break;
      }
    }
    return CloudProviderConnection(
      provider: localBackupProvider,
      folderPath: folderPath,
    );
  }

  Future<void> setLocalBackupPath(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    await setFolderPath(localBackup, folderPath);
    for (final legacyId in [icloud, googleDrive, dropbox]) {
      await prefs.remove(_keyFor(legacyId));
    }
  }

  Future<void> disconnectLocalBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(localBackup));
    for (final legacyId in [icloud, googleDrive, dropbox]) {
      await prefs.remove(_keyFor(legacyId));
    }
  }

  Future<bool> loadDeletedScriptsCustomFolderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deletedScriptsCustomFolderEnabledKey) ?? false;
  }

  Future<String> loadDeletedScriptsCustomFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return normalizePath(prefs.getString(_deletedScriptsCustomFolderPathKey));
  }

  Future<void> setDeletedScriptsCustomFolderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deletedScriptsCustomFolderEnabledKey, enabled);
  }

  Future<void> setDeletedScriptsCustomFolderPath(String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizePath(folderPath);
    if (normalized.isEmpty) {
      await prefs.remove(_deletedScriptsCustomFolderPathKey);
    } else {
      await prefs.setString(_deletedScriptsCustomFolderPathKey, normalized);
    }
  }

  Future<void> disconnectDeletedScriptsCustomFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deletedScriptsCustomFolderPathKey);
  }

  Future<String> resolveDeletedScriptsFolderPath() async {
    final customEnabled = await loadDeletedScriptsCustomFolderEnabled();
    final customPath = await loadDeletedScriptsCustomFolderPath();
    if (customEnabled && customPath.isNotEmpty) return customPath;
    final localBackup = await loadLocalBackupConnection();
    final rootPath = localBackup.folderPath.trim();
    if (rootPath.isEmpty) return '';
    return joinPath(rootPath, deletedScriptsFolderName);
  }

  Future<void> setFolderPath(String providerId, String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizePath(folderPath);
    if (normalized.isEmpty) {
      await prefs.remove(_keyFor(providerId));
    } else {
      await prefs.setString(_keyFor(providerId), normalized);
    }
  }

  Future<void> disconnect(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(providerId));
  }

  static String normalizePath(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[\r\n]'), '').trim();
  }

  static String joinPath(String left, String right) {
    final normalizedLeft = normalizePath(left);
    if (normalizedLeft.isEmpty) return normalizePath(right);
    final separator = normalizedLeft.contains('\\') ? '\\' : '/';
    if (normalizedLeft.endsWith('\\') || normalizedLeft.endsWith('/')) {
      return '$normalizedLeft$right';
    }
    return '$normalizedLeft$separator$right';
  }

  static bool isPathInside(String parent, String child) {
    final parentPath = _comparablePath(parent);
    final childPath = _comparablePath(child);
    if (parentPath.isEmpty || childPath.isEmpty) return false;
    return childPath.startsWith('$parentPath\\');
  }

  static String _comparablePath(String value) {
    return Directory(normalizePath(value))
        .absolute
        .path
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '')
        .toLowerCase();
  }
}
