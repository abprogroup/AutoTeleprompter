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
      subtitle: 'Connect your Dropbox account for AutoTeleprompter sync',
    ),
  ];

  static String _keyFor(String providerId) => 'cloudFolder.$providerId';

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
}
