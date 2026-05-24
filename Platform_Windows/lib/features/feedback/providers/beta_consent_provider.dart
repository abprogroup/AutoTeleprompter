import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const betaPrivacyPolicyVersion = '2026-05-24-beta-feedback-v1';
const betaFeedbackContactEmail = 'autoteleprompter@gmail.com';
const betaFeedbackControllerName = 'AB Pro Group';
const betaAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '5.0.2+17',
);

class BetaConsentState {
  final bool loaded;
  final String deviceKey;
  final String acceptedPolicyVersion;
  final String acceptedAtIso;
  final String acceptedAppVersion;

  const BetaConsentState({
    this.loaded = false,
    this.deviceKey = '',
    this.acceptedPolicyVersion = '',
    this.acceptedAtIso = '',
    this.acceptedAppVersion = '',
  });

  bool get hasAcceptedCurrentPolicy =>
      loaded && acceptedPolicyVersion == betaPrivacyPolicyVersion;

  BetaConsentState copyWith({
    bool? loaded,
    String? deviceKey,
    String? acceptedPolicyVersion,
    String? acceptedAtIso,
    String? acceptedAppVersion,
  }) {
    return BetaConsentState(
      loaded: loaded ?? this.loaded,
      deviceKey: deviceKey ?? this.deviceKey,
      acceptedPolicyVersion:
          acceptedPolicyVersion ?? this.acceptedPolicyVersion,
      acceptedAtIso: acceptedAtIso ?? this.acceptedAtIso,
      acceptedAppVersion: acceptedAppVersion ?? this.acceptedAppVersion,
    );
  }
}

class BetaConsentNotifier extends Notifier<BetaConsentState> {
  static const _deviceKeyKey = 'betaFeedbackDeviceKey';
  static const _acceptedPolicyVersionKey = 'betaPrivacyPolicyVersion';
  static const _acceptedAtKey = 'betaPrivacyAcceptedAt';
  static const _acceptedAppVersionKey = 'betaPrivacyAcceptedAppVersion';

  Future<void>? _loadFuture;

  @override
  BetaConsentState build() {
    _loadFuture = _load();
    return const BetaConsentState();
  }

  Future<void> ensureLoaded() async {
    await (_loadFuture ?? _load());
  }

  Future<void> acceptCurrentPolicy() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final acceptedAt = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(_acceptedPolicyVersionKey, betaPrivacyPolicyVersion);
    await prefs.setString(_acceptedAtKey, acceptedAt);
    await prefs.setString(_acceptedAppVersionKey, betaAppVersion);
    state = state.copyWith(
      acceptedPolicyVersion: betaPrivacyPolicyVersion,
      acceptedAtIso: acceptedAt,
      acceptedAppVersion: betaAppVersion,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceKey = prefs.getString(_deviceKeyKey) ?? '';
    if (deviceKey.isEmpty) {
      deviceKey = _newDeviceKey();
      await prefs.setString(_deviceKeyKey, deviceKey);
    }
    state = BetaConsentState(
      loaded: true,
      deviceKey: deviceKey,
      acceptedPolicyVersion: prefs.getString(_acceptedPolicyVersionKey) ?? '',
      acceptedAtIso: prefs.getString(_acceptedAtKey) ?? '',
      acceptedAppVersion: prefs.getString(_acceptedAppVersionKey) ?? '',
    );
  }

  String _newDeviceKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-');
  }
}

final betaConsentProvider =
    NotifierProvider<BetaConsentNotifier, BetaConsentState>(
  BetaConsentNotifier.new,
);
