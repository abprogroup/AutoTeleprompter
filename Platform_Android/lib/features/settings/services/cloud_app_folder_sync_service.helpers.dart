part of 'cloud_app_folder_sync_service.dart';

class CloudSyncedFile {
  final String id;
  final String name;
  final String providerId;
  final String? modifiedAtIso;
  final int? sizeBytes;

  const CloudSyncedFile({
    required this.id,
    required this.name,
    required this.providerId,
    this.modifiedAtIso,
    this.sizeBytes,
  });
}

class CloudSyncResult {
  final bool ok;
  final String message;

  const CloudSyncResult({
    required this.ok,
    required this.message,
  });
}

String _safeFileName(String title) {
  final clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? 'Untitled script' : clean;
}

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

String _recordingMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'application/octet-stream';
}

String _asciiHeaderJson(Map<String, Object?> value) {
  final encoded = jsonEncode(value);
  final buffer = StringBuffer();
  for (var i = 0; i < encoded.length; i++) {
    final unit = encoded.codeUnitAt(i);
    if (unit >= 0x20 && unit <= 0x7E) {
      buffer.writeCharCode(unit);
    } else {
      buffer.write(r'\u');
      buffer.write(unit.toRadixString(16).padLeft(4, '0'));
    }
  }
  return buffer.toString();
}

String _stableScriptFileName(String title) {
  final safeTitle = _safeFileName(title.isEmpty ? 'Untitled script' : title);
  if (RegExp(
    r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages)$',
    caseSensitive: false,
  ).hasMatch(safeTitle)) {
    return safeTitle;
  }
  final baseName = safeTitle.replaceFirst(
    RegExp(
      r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages|atp\.txt)$',
      caseSensitive: false,
    ),
    '',
  );
  return '${baseName.isEmpty ? 'Untitled script' : baseName}.txt';
}

bool _isInternalScriptArtifact(String fileName) {
  final lower = fileName.toLowerCase();
  return ScriptProjectCodec.isMetadataFileName(fileName) ||
      lower.endsWith('.atp') ||
      lower.endsWith('.atp.txt');
}

List<String> _legacyArtifactNamesFor(String primaryFileName) {
  final metadataName = ScriptProjectCodec.metadataFileNameFor(
    primaryFileName,
  );
  final base = primaryFileName.replaceFirst(
    RegExp(
      r'\.(?:docx?|rtf|txt|text|log|md|pdf|odt|pages)$',
      caseSensitive: false,
    ),
    '',
  );
  final names = <String>{
    metadataName,
    '$base.atp',
    '$base.atp.txt',
    '$primaryFileName.atp',
    '$primaryFileName.atp.txt',
  };
  return names
      .where((name) => name.trim().isNotEmpty && name != primaryFileName)
      .toList(growable: false);
}

String _driveQueryLiteral(String value) {
  return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}

String _providerFailure(String prefix, int statusCode, String body) {
  if (_isCloudAuthFailure(statusCode, body)) {
    return '$prefix. The cloud account authorization expired or was revoked. '
        'Reconnect this account, then try sync again.';
  }
  final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return '$prefix ($statusCode).';
  final clipped =
      compact.length > 220 ? '${compact.substring(0, 220)}...' : compact;
  return '$prefix ($statusCode): $clipped';
}

bool _isCloudAuthFailure(int statusCode, String body) {
  if (statusCode != 401) return false;
  final lower = body.toLowerCase();
  return lower.contains('invalid authentication credentials') ||
      lower.contains('invalid_access_token') ||
      lower.contains('invalid access token') ||
      lower.contains('unauthorized') ||
      lower.contains('expired') ||
      lower.contains('revoked');
}

String _cloudAuthFailureMessage() {
  return 'Cloud account authorization expired or was revoked. '
      'Reconnect this cloud account, then try sync again.';
}

String _dropboxProviderFailure(String prefix, int statusCode, String body) {
  if (_isDropboxAppFolderAccessIssue(body)) {
    return '$prefix. ${_dropboxAppFolderGuidance()}';
  }
  return _providerFailure(prefix, statusCode, body);
}

String _dropboxListFailure(Object error) {
  final compact = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_isDropboxAppFolderAccessIssue(compact)) {
    return 'Dropbox could not access its AutoTeleprompter app folder. '
        '${_dropboxAppFolderGuidance()}';
  }
  return compact;
}

bool _isDropboxAppFolderAccessIssue(String body) {
  final lower = body.toLowerCase();
  return lower.contains('invalid_access_token') ||
      lower.contains('invalid_access-token') ||
      lower.contains('path/not_found') ||
      lower.contains('"not_found"') ||
      lower.contains('not_found/');
}

String _dropboxAppFolderGuidance() {
  return 'Dropbox App Folder apps are intentionally stored under '
      'Apps/AutoTeleprompter. Keep scripts there. If that folder was deleted '
      'or Dropbox disconnected it, reconnect Dropbox and let AutoTeleprompter '
      'recreate the app folder.';
}
