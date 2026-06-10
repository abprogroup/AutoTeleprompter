import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const betaPrivacyPolicyVersion = '2026-05-24-beta-feedback-v1';
const betaSpeechDisclosureVersion = '2026-05-30-speech-disclosure-v1';
const betaCloudDisclosureVersion = '2026-06-01-cloud-disclosure-v1';
const betaFeedbackContactEmail = 'autoteleprompter@gmail.com';
const betaFeedbackControllerName = 'AB Pro Group';
const betaAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '5.0.7+31',
);

class BetaConsentState {
  final bool loaded;
  final String deviceKey;
  final String acceptedPolicyVersion;
  final String acceptedSpeechDisclosureVersion;
  final String acceptedCloudDisclosureVersion;
  final String acceptedAtIso;
  final String acceptedAppVersion;

  const BetaConsentState({
    this.loaded = false,
    this.deviceKey = '',
    this.acceptedPolicyVersion = '',
    this.acceptedSpeechDisclosureVersion = '',
    this.acceptedCloudDisclosureVersion = '',
    this.acceptedAtIso = '',
    this.acceptedAppVersion = '',
  });

  bool get hasAcceptedFeedbackPolicy =>
      loaded && acceptedPolicyVersion == betaPrivacyPolicyVersion;

  bool get hasAcceptedSpeechDisclosure =>
      loaded && acceptedSpeechDisclosureVersion == betaSpeechDisclosureVersion;

  bool get hasAcceptedCloudDisclosure =>
      loaded && acceptedCloudDisclosureVersion == betaCloudDisclosureVersion;

  bool get hasAcceptedCurrentPolicy =>
      hasAcceptedFeedbackPolicy &&
      hasAcceptedSpeechDisclosure &&
      hasAcceptedCloudDisclosure;

  bool get hasAcceptedFeedbackAndSpeech =>
      hasAcceptedFeedbackPolicy && hasAcceptedSpeechDisclosure;

  BetaConsentState copyWith({
    bool? loaded,
    String? deviceKey,
    String? acceptedPolicyVersion,
    String? acceptedSpeechDisclosureVersion,
    String? acceptedCloudDisclosureVersion,
    String? acceptedAtIso,
    String? acceptedAppVersion,
  }) {
    return BetaConsentState(
      loaded: loaded ?? this.loaded,
      deviceKey: deviceKey ?? this.deviceKey,
      acceptedPolicyVersion:
          acceptedPolicyVersion ?? this.acceptedPolicyVersion,
      acceptedSpeechDisclosureVersion: acceptedSpeechDisclosureVersion ??
          this.acceptedSpeechDisclosureVersion,
      acceptedCloudDisclosureVersion:
          acceptedCloudDisclosureVersion ?? this.acceptedCloudDisclosureVersion,
      acceptedAtIso: acceptedAtIso ?? this.acceptedAtIso,
      acceptedAppVersion: acceptedAppVersion ?? this.acceptedAppVersion,
    );
  }
}

class BetaConsentNotifier extends Notifier<BetaConsentState> {
  static const _deviceKeyKey = 'betaFeedbackDeviceKey';
  static const _acceptedPolicyVersionKey = 'betaPrivacyPolicyVersion';
  static const _acceptedSpeechDisclosureVersionKey =
      'betaSpeechDisclosureVersion';
  static const _acceptedCloudDisclosureVersionKey =
      'betaCloudDisclosureVersion';
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
    await acceptFeedbackPolicy();
    await acceptSpeechDisclosure();
    await acceptCloudDisclosure();
  }

  Future<void> acceptFeedbackPolicy() async {
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

  Future<void> acceptSpeechDisclosure() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final acceptedAt = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(
      _acceptedSpeechDisclosureVersionKey,
      betaSpeechDisclosureVersion,
    );
    await prefs.setString(_acceptedAtKey, acceptedAt);
    await prefs.setString(_acceptedAppVersionKey, betaAppVersion);
    state = state.copyWith(
      acceptedSpeechDisclosureVersion: betaSpeechDisclosureVersion,
      acceptedAtIso: acceptedAt,
      acceptedAppVersion: betaAppVersion,
    );
  }

  Future<void> acceptCloudDisclosure() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final acceptedAt = DateTime.now().toUtc().toIso8601String();
    await prefs.setString(
      _acceptedCloudDisclosureVersionKey,
      betaCloudDisclosureVersion,
    );
    await prefs.setString(_acceptedAtKey, acceptedAt);
    await prefs.setString(_acceptedAppVersionKey, betaAppVersion);
    state = state.copyWith(
      acceptedCloudDisclosureVersion: betaCloudDisclosureVersion,
      acceptedAtIso: acceptedAt,
      acceptedAppVersion: betaAppVersion,
    );
  }

  Future<void> withdrawConsent() async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_acceptedPolicyVersionKey);
    await prefs.remove(_acceptedSpeechDisclosureVersionKey);
    await prefs.remove(_acceptedCloudDisclosureVersionKey);
    await prefs.remove(_acceptedAtKey);
    await prefs.remove(_acceptedAppVersionKey);
    state = state.copyWith(
      acceptedPolicyVersion: '',
      acceptedSpeechDisclosureVersion: '',
      acceptedCloudDisclosureVersion: '',
      acceptedAtIso: '',
      acceptedAppVersion: '',
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
      acceptedSpeechDisclosureVersion:
          prefs.getString(_acceptedSpeechDisclosureVersionKey) ?? '',
      acceptedCloudDisclosureVersion:
          prefs.getString(_acceptedCloudDisclosureVersionKey) ?? '',
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
