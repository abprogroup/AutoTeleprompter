import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'protected_data_service.dart';

class EncryptedFileStore {
  static const int schemaVersion = 1;
  static const String provider = 'windows-dpapi-current-user';

  EncryptedFileStore({
    ProtectedDataService protectedData = const DpapiProtectedDataService(),
    Future<Directory> Function()? baseDirectory,
  })  : _protectedData = protectedData,
        _baseDirectory = baseDirectory;

  final ProtectedDataService _protectedData;
  final Future<Directory> Function()? _baseDirectory;

  Future<File> writeBytes({
    required String collection,
    required String id,
    required String extension,
    required List<int> bytes,
    required String kind,
    bool compress = true,
  }) async {
    final dir = await _ensureCollection(collection);
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

  Future<Uint8List> readBytes(File file, {required String kind}) async {
    final raw = await file.readAsString();
    return unprotectEnvelopeAsync(raw, expectedKind: kind);
  }

  Future<File?> fileFor({
    required String collection,
    required String id,
    required String extension,
  }) async {
    final dir = await _ensureCollection(collection);
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

  String protectToEnvelope(
    List<int> bytes, {
    required String kind,
    bool compress = true,
  }) {
    final plainBytes = Uint8List.fromList(
      compress ? gzip.encode(bytes) : bytes,
    );
    final protectedBytes = _protectedData.protect(plainBytes, kind: kind);
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'provider': provider,
      'kind': kind,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'compressed': compress,
      'ciphertextBase64': base64Encode(protectedBytes),
    });
  }

  Future<String> protectToEnvelopeAsync(
    List<int> bytes, {
    required String kind,
    bool compress = true,
  }) async {
    final source = Uint8List.fromList(bytes);
    if (_protectedData is DpapiProtectedDataService) {
      return Isolate.run(
        () => _protectDpapiEnvelope(source, kind: kind, compress: compress),
      );
    }
    final plainBytes = Uint8List.fromList(
      compress ? await Isolate.run(() => gzip.encode(source)) : source,
    );
    final protectedBytes = _protectedData.protect(plainBytes, kind: kind);
    return _envelopeJson(kind, compress, protectedBytes);
  }

  Uint8List unprotectEnvelope(String envelope, {required String expectedKind}) {
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
    final protectedBytes = base64Decode(decoded['ciphertextBase64'] as String);
    final plainBytes = _protectedData.unprotect(
      Uint8List.fromList(protectedBytes),
      expectedKind: expectedKind,
    );
    final compressed = decoded['compressed'] == true;
    return Uint8List.fromList(
        compressed ? gzip.decode(plainBytes) : plainBytes);
  }

  Future<Uint8List> unprotectEnvelopeAsync(
    String envelope, {
    required String expectedKind,
  }) async {
    if (_protectedData is DpapiProtectedDataService) {
      return Isolate.run(
        () => _unprotectDpapiEnvelope(
          envelope,
          expectedKind: expectedKind,
        ),
      );
    }
    return unprotectEnvelope(envelope, expectedKind: expectedKind);
  }

  Future<Directory> _ensureCollection(String collection) async {
    final base = _baseDirectory == null
        ? await getApplicationSupportDirectory()
        : await _baseDirectory();
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}secure_storage'
      '${Platform.pathSeparator}${sanitizeId(collection)}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String sanitizeId(String id) {
    final trimmed = id.trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : id.trim();
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}

String _protectDpapiEnvelope(
  Uint8List bytes, {
  required String kind,
  required bool compress,
}) {
  final plainBytes = Uint8List.fromList(compress ? gzip.encode(bytes) : bytes);
  final protectedBytes =
      const DpapiProtectedDataService().protect(plainBytes, kind: kind);
  return _envelopeJson(kind, compress, protectedBytes);
}

Uint8List _unprotectDpapiEnvelope(
  String envelope, {
  required String expectedKind,
}) {
  final decoded = jsonDecode(envelope) as Map<String, dynamic>;
  if (decoded['schemaVersion'] != EncryptedFileStore.schemaVersion) {
    throw StateError('Unsupported encrypted payload version.');
  }
  if (decoded['provider'] != EncryptedFileStore.provider) {
    throw StateError('Unsupported encrypted payload provider.');
  }
  if (decoded['kind'] != expectedKind) {
    throw StateError('Encrypted payload kind mismatch.');
  }
  final protectedBytes = base64Decode(decoded['ciphertextBase64'] as String);
  final plainBytes = const DpapiProtectedDataService().unprotect(
    Uint8List.fromList(protectedBytes),
    expectedKind: expectedKind,
  );
  final compressed = decoded['compressed'] == true;
  return Uint8List.fromList(compressed ? gzip.decode(plainBytes) : plainBytes);
}

String _envelopeJson(String kind, bool compressed, Uint8List protectedBytes) {
  return jsonEncode({
    'schemaVersion': EncryptedFileStore.schemaVersion,
    'provider': EncryptedFileStore.provider,
    'kind': kind,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'compressed': compressed,
    'ciphertextBase64': base64Encode(protectedBytes),
  });
}
