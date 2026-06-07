enum AccountBackendRole {
  free,
  pro,
  admin;

  static AccountBackendRole fromWire(Object? value) {
    switch ((value ?? '').toString().trim().toLowerCase()) {
      case 'admin':
        return AccountBackendRole.admin;
      case 'pro':
        return AccountBackendRole.pro;
      default:
        return AccountBackendRole.free;
    }
  }

  String get wireName => name;
}

class AccountBackendProfile {
  final String accountId;
  final String email;
  final String status;
  final AccountBackendRole role;
  final DateTime? entitlementExpiresAt;
  final bool entitlementRevoked;
  final DateTime? serverTime;

  const AccountBackendProfile({
    required this.accountId,
    required this.email,
    required this.status,
    required this.role,
    this.entitlementExpiresAt,
    this.entitlementRevoked = false,
    this.serverTime,
  });

  bool get isDisabled => status == 'disabled';

  bool get hasPremiumAccess =>
      !isDisabled &&
      !entitlementRevoked &&
      (role == AccountBackendRole.pro || role == AccountBackendRole.admin) &&
      (entitlementExpiresAt == null ||
          entitlementExpiresAt!.isAfter(DateTime.now().toUtc()));

  bool get isAdmin =>
      !isDisabled && !entitlementRevoked && role == AccountBackendRole.admin;

  factory AccountBackendProfile.fromJson(Map<String, dynamic> json) {
    final profile = _asMap(json['profile']);
    final entitlement = _asMap(json['entitlement']);
    return AccountBackendProfile(
      accountId: (profile['user_id'] ?? profile['id'] ?? '').toString(),
      email: (profile['email'] ?? '').toString(),
      status: (profile['status'] ?? 'active').toString(),
      role: AccountBackendRole.fromWire(entitlement['role']),
      entitlementExpiresAt: _date(entitlement['expires_at']),
      entitlementRevoked: entitlement['revoked_at'] != null,
      serverTime: _date(json['serverTime']),
    );
  }
}

class AccountBackendSession {
  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String? userId;
  final String? email;

  const AccountBackendSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.userId,
    this.email,
  });

  factory AccountBackendSession.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final expiresIn = json['expires_in'];
    return AccountBackendSession(
      accessToken: (json['access_token'] ?? '').toString(),
      refreshToken: json['refresh_token']?.toString(),
      expiresAt: expiresIn is int
          ? DateTime.now().toUtc().add(Duration(seconds: expiresIn))
          : null,
      userId: user['id']?.toString(),
      email: user['email']?.toString(),
    );
  }
}

class AccountBackendError implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const AccountBackendError(this.code, this.message, {this.statusCode});

  @override
  String toString() => 'AccountBackendError($code, $message)';
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
