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
  static const String icloud = 'icloud';
  static const String googleDrive = 'google_drive';
  static const String dropbox = 'dropbox';

  static const providers = [
    CloudProviderDefinition(
      id: icloud,
      label: 'Apple iCloud Drive',
      subtitle:
          'Choose the local iCloud Drive folder already synced on this PC',
    ),
    CloudProviderDefinition(
      id: googleDrive,
      label: 'Google Drive',
      subtitle:
          'Connect your account, or choose a local Drive folder synced on this PC',
    ),
    CloudProviderDefinition(
      id: dropbox,
      label: 'Dropbox',
      subtitle:
          'Connect your account, or choose a local Dropbox folder synced on this PC',
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
