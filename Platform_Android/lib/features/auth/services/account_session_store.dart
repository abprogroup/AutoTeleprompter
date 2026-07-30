import 'dart:convert';

import '../../../core/security/encrypted_file_store.dart';
import 'account_backend_models.dart';

class AccountSessionSnapshot {
  final String accessToken;
  final String? refreshToken;
  final String? userId;
  final String? email;
  final String? deviceId;
  final AccountBackendRole role;
  final DateTime? expiresAt;
  final DateTime? lastServerTimestamp;
  final String? graceToken;
  final DateTime? graceExpiresAt;

  const AccountSessionSnapshot({
    required this.accessToken,
    this.refreshToken,
    this.userId,
    this.email,
    this.deviceId,
    this.role = AccountBackendRole.free,
    this.expiresAt,
    this.lastServerTimestamp,
    this.graceToken,
    this.graceExpiresAt,
  });

  Map<String, Object?> toJson() => {
        'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (userId != null) 'userId': userId,
        if (email != null) 'email': email,
        if (deviceId != null) 'deviceId': deviceId,
        'role': role.wireName,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (lastServerTimestamp != null)
          'lastServerTimestamp': lastServerTimestamp!.toIso8601String(),
        if (graceToken != null) 'graceToken': graceToken,
        if (graceExpiresAt != null)
          'graceExpiresAt': graceExpiresAt!.toIso8601String(),
      };

  factory AccountSessionSnapshot.fromJson(Map<String, dynamic> json) {
    return AccountSessionSnapshot(
      accessToken: (json['accessToken'] ?? '').toString(),
      refreshToken: json['refreshToken']?.toString(),
      userId: json['userId']?.toString(),
      email: json['email']?.toString(),
      deviceId: json['deviceId']?.toString(),
      role: AccountBackendRole.fromWire(json['role']),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      lastServerTimestamp:
          DateTime.tryParse(json['lastServerTimestamp']?.toString() ?? ''),
      graceToken: json['graceToken']?.toString(),
      graceExpiresAt:
          DateTime.tryParse(json['graceExpiresAt']?.toString() ?? ''),
    );
  }
}

class AccountSessionStore {
  AccountSessionStore({EncryptedFileStore? fileStore})
      : _fileStore = fileStore ?? EncryptedFileStore();

  static const _collection = 'account_sessions';
  static const _id = 'current';
  static const _extension = 'session';
  static const _kind = 'account-backend-session';

  final EncryptedFileStore _fileStore;

  Future<void> save(AccountSessionSnapshot snapshot) async {
    await _fileStore.writeBytes(
      collection: _collection,
      id: _id,
      extension: _extension,
      kind: _kind,
      bytes: utf8.encode(jsonEncode(snapshot.toJson())),
    );
  }

  Future<AccountSessionSnapshot?> read() async {
    final file = await _fileStore.fileFor(
      collection: _collection,
      id: _id,
      extension: _extension,
    );
    if (file == null) return null;
    final bytes = await _fileStore.readBytes(file, kind: _kind);
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return AccountSessionSnapshot.fromJson(decoded);
  }

  Future<void> clear() async {
    await _fileStore.delete(
      collection: _collection,
      id: _id,
      extension: _extension,
    );
  }
}
