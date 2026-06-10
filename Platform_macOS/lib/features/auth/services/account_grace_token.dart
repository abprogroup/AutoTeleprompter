import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'account_backend_models.dart';

const _graceKeyId = 'staging-20260608-rsa2';
const _gracePublicModulusHex =
    'a02bfafa07a8faeaf41a133d48cfd5da242f9189f5410794b3e8ed5f6eaf0f71d5963bb0f9855734ba792b73bda04dea5f31ccde2a03a21a30398e8afeeee10e99e0a05f97b3e84436d134132f4a4160d40dfc1fef9a8d37de3057c38ce6be69bf2dd0430b67d91fca6badcc34dc96d7c4ab89966f10de1c427a5f710f8178521dcff1a8297deac4224cf829584e72d4e13f11fa13c390abf94d425ab8313cadf389ab33558ef38f94388333483314866ef79bb77953888c5c381c4cb7167fa539f4f9edc1b12f54a54b96cda2523c8e1d279bcf434137584c8061b23aad4c0f2a84cdeb642cd513480e83e09e8f6c662c9111c1175284d6682a19fa8da04915';
const _gracePublicExponentHex = '010001';
const _sha256DigestInfoPrefixHex = '3031300d060960864801650304020105000420';

class AccountGracePayload {
  final String accountId;
  final String email;
  final String deviceId;
  final AccountBackendRole role;
  final String status;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime? entitlementExpiresAt;

  const AccountGracePayload({
    required this.accountId,
    required this.email,
    required this.deviceId,
    required this.role,
    required this.status,
    required this.issuedAt,
    required this.expiresAt,
    this.entitlementExpiresAt,
  });

  bool get entitlementActive => status == 'active';

  bool hasPremiumAccessAt(DateTime now) {
    final utcNow = now.toUtc();
    if (!entitlementActive || !expiresAt.isAfter(utcNow)) return false;
    if (role == AccountBackendRole.admin) return true;
    if (role != AccountBackendRole.pro) return false;
    final billingEnd = entitlementExpiresAt;
    return billingEnd == null || billingEnd.isAfter(utcNow);
  }

  bool isAdminAt(DateTime now) =>
      entitlementActive &&
      role == AccountBackendRole.admin &&
      expiresAt.isAfter(now.toUtc());
}

class AccountGraceTokenVerifier {
  const AccountGraceTokenVerifier();

  AccountGracePayload? verify(
    String? token, {
    required String expectedDeviceId,
    DateTime? lastServerTimestamp,
    DateTime? now,
  }) {
    final value = token?.trim();
    if (value == null || value.isEmpty) return null;
    final parts = value.split('.');
    if (parts.length != 2) return null;
    final payloadPart = parts[0];
    final signature = _base64UrlDecode(parts[1]);
    if (!_verifySignature(payloadPart, signature)) return null;

    final payloadJson = utf8.decode(_base64UrlDecode(payloadPart));
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    if ((payload['kid'] ?? '').toString() != _graceKeyId) return null;
    
    final aud = (payload['aud'] ?? '').toString();
    if (aud != 'autoteleprompter-windows' && aud != 'autoteleprompter-macos') {
      return null;
    }
    if ((payload['device_id'] ?? '').toString() != expectedDeviceId) {
      return null;
    }

    final issuedAt = _date(payload['issued_at']);
    final expiresAt = _date(payload['grace_expires_at']);
    if (issuedAt == null || expiresAt == null) return null;
    final localNow = (now ?? DateTime.now().toUtc()).toUtc();
    if (lastServerTimestamp != null &&
        localNow.isBefore(
          lastServerTimestamp.toUtc().subtract(const Duration(minutes: 5)),
        )) {
      return null;
    }
    if (localNow.isBefore(issuedAt.subtract(const Duration(minutes: 5)))) {
      return null;
    }
    if (!expiresAt.isAfter(localNow)) return null;

    final grace = AccountGracePayload(
      accountId: (payload['account_id'] ?? '').toString(),
      email: (payload['email'] ?? '').toString(),
      deviceId: (payload['device_id'] ?? '').toString(),
      role: AccountBackendRole.fromWire(payload['role']),
      status: (payload['status'] ?? 'active').toString(),
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      entitlementExpiresAt: _date(payload['entitlement_expires_at']),
    );
    return grace.hasPremiumAccessAt(localNow) ? grace : null;
  }

  bool _verifySignature(String payloadPart, Uint8List signature) {
    final modulus = _bigIntFromHex(_gracePublicModulusHex);
    final exponent = _bigIntFromHex(_gracePublicExponentHex);
    final modulusLength = (_gracePublicModulusHex.length / 2).ceil();
    if (signature.length != modulusLength) return false;

    final signatureInt = _bigIntFromBytes(signature);
    final decoded = _bigIntToFixedBytes(
      signatureInt.modPow(exponent, modulus),
      modulusLength,
    );
    final digest = sha256.convert(ascii.encode(payloadPart)).bytes;
    final expectedDigestInfo = Uint8List.fromList([
      ..._hexToBytes(_sha256DigestInfoPrefixHex),
      ...digest,
    ]);
    final paddingLength = modulusLength - expectedDigestInfo.length - 3;
    if (paddingLength < 8) return false;
    final expected = Uint8List.fromList([
      0x00,
      0x01,
      ...List<int>.filled(paddingLength, 0xff),
      0x00,
      ...expectedDigestInfo,
    ]);
    return _constantTimeEquals(decoded, expected);
  }
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}

Uint8List _base64UrlDecode(String value) {
  final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + ((4 - normalized.length % 4) % 4),
    '=',
  );
  return base64Decode(padded);
}

BigInt _bigIntFromHex(String hex) => BigInt.parse(hex, radix: 16);

BigInt _bigIntFromBytes(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToFixedBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var remaining = value;
  for (var index = length - 1; index >= 0; index--) {
    bytes[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining = remaining >> 8;
  }
  return bytes;
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

bool _constantTimeEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var diff = 0;
  for (var i = 0; i < left.length; i++) {
    diff |= left[i] ^ right[i];
  }
  return diff == 0;
}
