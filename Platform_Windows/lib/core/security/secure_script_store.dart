import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'encrypted_file_store.dart';

class SecureScriptData {
  final String text;
  final String? historyJson;

  const SecureScriptData({
    required this.text,
    this.historyJson,
  });
}

class SecureScriptStore {
  static const int storageVersion = 1;
  static const String recordIdKey = 'secureRecordId';
  static const String storageVersionKey = 'secureStorageVersion';

  SecureScriptStore({EncryptedFileStore? fileStore})
      : _fileStore = fileStore ?? EncryptedFileStore();

  final EncryptedFileStore _fileStore;

  Future<String> save({
    required String recordId,
    required String text,
    String? historyJson,
  }) async {
    final safeId = EncryptedFileStore.sanitizeId(recordId);
    final bytes = await Isolate.run(
      () => utf8.encode(jsonEncode({
        'text': text,
        if (historyJson != null) 'historyJson': historyJson,
      })),
    );
    await _fileStore.writeBytes(
      collection: 'scripts',
      id: safeId,
      extension: 'atps',
      kind: 'script-record',
      bytes: bytes,
    );
    return safeId;
  }

  Future<SecureScriptData?> read(String? recordId) async {
    if (recordId == null || recordId.trim().isEmpty) return null;
    final file = await _fileStore.fileFor(
      collection: 'scripts',
      id: recordId,
      extension: 'atps',
    );
    if (file == null) return null;
    final bytes = await _fileStore.readBytes(file, kind: 'script-record');
    final decoded = await Isolate.run(
      () => jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
    return SecureScriptData(
      text: decoded['text'] as String? ?? '',
      historyJson: decoded['historyJson'] as String?,
    );
  }

  Future<SecureScriptData?> readFromMetadata(Map<String, dynamic> meta) async {
    final secure = await read(meta[recordIdKey] as String?);
    if (secure != null) return secure;
    final legacyText = meta['fullText'];
    if (legacyText is String) {
      return SecureScriptData(
        text: legacyText,
        historyJson: meta['historyJson'] as String?,
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> secureMetadata(
    Map<String, dynamic> meta, {
    required String text,
    String? historyJson,
  }) async {
    final sessionId = (meta['sessionId'] as String?) ??
        'session_${DateTime.now().microsecondsSinceEpoch}';
    final recordId = await save(
      recordId: sessionId,
      text: text,
      historyJson: historyJson,
    );
    final next = Map<String, dynamic>.from(meta)
      ..['sessionId'] = sessionId
      ..[recordIdKey] = recordId
      ..[storageVersionKey] = storageVersion
      ..remove('fullText')
      ..remove('historyJson')
      ..remove('snippet');
    return next;
  }

  Future<List<String>> migrateRecentMetadata(List<String> rawRecents) async {
    final result = <String>[];
    for (var i = 0; i < rawRecents.length; i++) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(rawRecents[i]));
        if (decoded[recordIdKey] is String) {
          decoded
            ..remove('fullText')
            ..remove('historyJson')
            ..remove('snippet');
          result.add(jsonEncode(decoded));
          continue;
        }
        final legacyText = decoded['fullText'];
        if (legacyText is String && legacyText.isNotEmpty) {
          decoded['sessionId'] ??=
              'rec_${DateTime.now().millisecondsSinceEpoch}_$i';
          final secured = await secureMetadata(
            decoded,
            text: legacyText,
            historyJson: decoded['historyJson'] as String?,
          );
          result.add(jsonEncode(secured));
        } else {
          decoded
            ..remove('fullText')
            ..remove('historyJson')
            ..remove('snippet');
          result.add(jsonEncode(decoded));
        }
      } catch (_) {
        result.add(rawRecents[i]);
      }
    }
    return result;
  }

  Future<String?> migrateLastScript({
    required String? lastScript,
    required String? lastTitle,
    required String? fallbackSessionId,
  }) async {
    if (lastScript == null || lastScript.trim().isEmpty) return null;
    if (fallbackSessionId != null &&
        fallbackSessionId.isNotEmpty &&
        await read(fallbackSessionId) != null) {
      return fallbackSessionId;
    }
    final recordId = fallbackSessionId ??
        'last_${DateTime.now().microsecondsSinceEpoch.toString()}';
    return save(recordId: recordId, text: lastScript);
  }

  static String? recordIdFromMetadata(Map<String, dynamic> meta) {
    final value = meta[recordIdKey];
    return value is String && value.isNotEmpty ? value : null;
  }
}

class SecureFileExport {
  static String decryptedExportPathFor(File encryptedFile) {
    final name = encryptedFile.path.split(Platform.pathSeparator).last;
    return name.endsWith('.atpe')
        ? name.substring(0, name.length - '.atpe'.length)
        : '$name.decrypted';
  }
}
