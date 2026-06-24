import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class EncryptedFileStore {
  static const int schemaVersion = 1;
  static const String provider = 'secure-storage-aes-gcm-v1';
  static const String _keyName = 'autoteleprompter.encryptedFileStoreKey.v1';

  EncryptedFileStore({
    FlutterSecureStorage? secureStorage,
    Future<Directory> Function()? baseDirectory,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _baseDirectory = baseDirectory;

  final FlutterSecureStorage _secureStorage;
  final Future<Directory> Function()? _baseDirectory;

  Future<Uint8List> readBytes(File file, {required String kind}) async {
    return unprotectEnvelopeAsync(
      await file.readAsString(),
      expectedKind: kind,
    );
  }

  Future<File> writeBytes({
    required String collection,
    required String id,
    required String extension,
    required List<int> bytes,
    required String kind,
    bool compress = true,
  }) async {
    final dir = await ensureCollection(collection);
    final safeId = sanitizeId(id);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$safeId.$extension.atpe',
    );
    final envelope = await protectToEnvelopeAsync(
      bytes,
      kind: kind,
      compress: compress,
    );
    await file.writeAsString(envelope, flush: true);
    return file;
  }

  Future<File?> fileFor({
    required String collection,
    required String id,
    required String extension,
  }) async {
    final dir = await ensureCollection(collection);
    final safeId = sanitizeId(id);
    final file = File(
      '${dir.path}${Platform.pathSeparator}$safeId.$extension.atpe',
    );
    return await file.exists() ? file : null;
  }

  Future<void> delete({
    required String collection,
    required String id,
    required String extension,
  }) async {
    final file = await fileFor(
      collection: collection,
      id: id,
      extension: extension,
    );
    if (file != null) await file.delete();
  }

  Future<String> protectToEnvelopeAsync(
    List<int> bytes, {
    required String kind,
    bool compress = true,
  }) async {
    final key = SecretKey(await _readOrCreateKey());
    final nonce = _randomBytes(12);
    final plain = Uint8List.fromList(compress ? gzip.encode(bytes) : bytes);
    final box = await AesGcm.with256bits().encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'provider': provider,
      'kind': kind,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'compressed': compress,
      'nonceBase64': base64Encode(box.nonce),
      'ciphertextBase64': base64Encode(box.cipherText),
      'macBase64': base64Encode(box.mac.bytes),
    });
  }

  Future<Uint8List> unprotectEnvelopeAsync(
    String envelope, {
    required String expectedKind,
  }) async {
    final decoded = jsonDecode(envelope) as Map<String, dynamic>;
    if (decoded['schemaVersion'] != schemaVersion) {
      throw StateError('Unsupported encrypted payload version.');
    }
    if (decoded['provider'] != provider) {
      throw StateError('Unsupported encrypted payload provider.');
    }
    if (decoded['kind'] != expectedKind) {
      throw StateError('Encrypted payload kind mismatch.');
    }
    final key = SecretKey(await _readOrCreateKey());
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(decoded['ciphertextBase64'] as String),
        nonce: base64Decode(decoded['nonceBase64'] as String),
        mac: Mac(base64Decode(decoded['macBase64'] as String)),
      ),
      secretKey: key,
    );
    return Uint8List.fromList(
      decoded['compressed'] == true ? gzip.decode(clear) : clear,
    );
  }

  Future<Directory> ensureCollection(String collection) async {
    final base = await _resolveBaseDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}secure_storage'
      '${Platform.pathSeparator}${sanitizeId(collection)}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>> _readOrCreateKey() async {
    try {
      final existing = await _secureStorage.read(key: _keyName);
      if (existing != null && existing.isNotEmpty) {
        return base64Decode(existing);
      }
    } catch (_) {
      return _readOrCreateFallbackKey();
    }
    final key = _randomBytes(32);
    try {
      await _secureStorage.write(key: _keyName, value: base64Encode(key));
    } catch (_) {
      return _readOrCreateFallbackKey(seed: key);
    }
    return key;
  }

  Future<Directory> _resolveBaseDirectory() async {
    if (_baseDirectory != null) return _baseDirectory();
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      final dir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'autoteleprompter_ios_secure_store',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
  }

  Future<List<int>> _readOrCreateFallbackKey({List<int>? seed}) async {
    final base = await _resolveBaseDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}secure_storage',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$_keyName.key');
    if (await file.exists()) {
      final existing = await file.readAsString();
      if (existing.trim().isNotEmpty) return base64Decode(existing);
    }
    final key = seed ?? _randomBytes(32);
    await file.writeAsString(base64Encode(key), flush: true);
    return key;
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  static String sanitizeId(String id) {
    final trimmed = id.trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : id.trim();
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
