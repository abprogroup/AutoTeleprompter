part of 'auth_provider.dart';

class AuthState {
  final String? email;
  final bool isPro;
  final bool isAdmin;
  final String? licenseKey;
  final bool accountBackendEnabled;
  final String? backendAccountId;
  final AccountBackendRole backendRole;
  final String backendStatus;
  final String? backendError;
  final DateTime? backendTokenExpiry;
  final String backendEntitlementStatus;
  final DateTime? entitlementExpiresAt;
  final bool entitlementRevoked;
  final DateTime? offlineGraceExpiry;
  final String? deviceId;
  final DateTime? lastServerTimestamp;
  final bool rememberMe;
  final String? lastEmailUsed;

  AuthState({
    this.email,
    this.isPro = false,
    this.isAdmin = false,
    this.licenseKey,
    this.accountBackendEnabled = false,
    this.backendAccountId,
    this.backendRole = AccountBackendRole.free,
    this.backendStatus = 'disabled',
    this.backendError,
    this.backendTokenExpiry,
    this.backendEntitlementStatus = 'active',
    this.entitlementExpiresAt,
    this.entitlementRevoked = false,
    this.offlineGraceExpiry,
    this.deviceId,
    this.lastServerTimestamp,
    this.rememberMe = true,
    this.lastEmailUsed,
  });

  bool get isSignedIn => email != null && email!.trim().isNotEmpty;

  bool get hasPremiumAccess => isSignedIn && isPro;

  bool get isBackendActive =>
      accountBackendEnabled && backendStatus == 'active';

  String get entitlementStatus {
    if (backendStatus == 'disabledAccount') return 'disabled';
    if (backendEntitlementStatus == 'revoked') return 'revoked';
    if (backendEntitlementStatus == 'expired') return 'expired';
    if (entitlementRevoked) return 'revoked';
    final expiresAt = entitlementExpiresAt;
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      return 'expired';
    }
    if (backendRole == AccountBackendRole.admin ||
        backendRole == AccountBackendRole.pro) {
      return 'active';
    }
    return 'free';
  }

  String get roleLabel {
    switch (backendRole) {
      case AccountBackendRole.admin:
        return 'Admin';
      case AccountBackendRole.pro:
        return 'Pro';
      case AccountBackendRole.free:
        return 'Free';
    }
  }

  bool get isCheckingBackendAccess =>
      accountBackendEnabled &&
      const {
        'storedSession',
        'refreshingStoredSession',
        'requestingCode',
        'verifyingCode',
      }.contains(backendStatus);

  AuthState copyWith({
    String? email,
    bool? isPro,
    bool? isAdmin,
    String? licenseKey,
    bool? accountBackendEnabled,
    String? backendAccountId,
    AccountBackendRole? backendRole,
    String? backendStatus,
    String? backendError,
    DateTime? backendTokenExpiry,
    String? backendEntitlementStatus,
    DateTime? entitlementExpiresAt,
    bool clearEntitlementExpiresAt = false,
    bool? entitlementRevoked,
    DateTime? offlineGraceExpiry,
    String? deviceId,
    DateTime? lastServerTimestamp,
    bool? rememberMe,
    String? lastEmailUsed,
  }) {
    return AuthState(
      email: email ?? this.email,
      isPro: isPro ?? this.isPro,
      isAdmin: isAdmin ?? this.isAdmin,
      licenseKey: licenseKey ?? this.licenseKey,
      accountBackendEnabled:
          accountBackendEnabled ?? this.accountBackendEnabled,
      backendAccountId: backendAccountId ?? this.backendAccountId,
      backendRole: backendRole ?? this.backendRole,
      backendStatus: backendStatus ?? this.backendStatus,
      backendError: backendError ?? this.backendError,
      backendTokenExpiry: backendTokenExpiry ?? this.backendTokenExpiry,
      backendEntitlementStatus:
          backendEntitlementStatus ?? this.backendEntitlementStatus,
      entitlementExpiresAt: clearEntitlementExpiresAt
          ? null
          : entitlementExpiresAt ?? this.entitlementExpiresAt,
      entitlementRevoked: entitlementRevoked ?? this.entitlementRevoked,
      offlineGraceExpiry: offlineGraceExpiry ?? this.offlineGraceExpiry,
      deviceId: deviceId ?? this.deviceId,
      lastServerTimestamp: lastServerTimestamp ?? this.lastServerTimestamp,
      rememberMe: rememberMe ?? this.rememberMe,
      lastEmailUsed: lastEmailUsed ?? this.lastEmailUsed,
    );
  }
}
