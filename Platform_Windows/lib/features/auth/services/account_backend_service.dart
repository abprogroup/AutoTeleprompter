import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'account_backend_config.dart';
import 'account_backend_models.dart';

class AccountBackendService {
  AccountBackendService({
    AccountBackendConfig config = const AccountBackendConfig(),
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  })  : _config = config,
        _client = client ?? HttpClient();

  final AccountBackendConfig _config;
  final HttpClient _client;
  final Duration timeout;

  bool get isConfigured => _config.isConfigured;

  Future<void> requestLoginCode(String email) async {
    _requireConfigured();
    await _postJson(
      _config.authUri('otp'),
      {
        'email': email.trim(),
        'create_user': true,
      },
      includeAuth: false,
    );
  }

  Future<AccountBackendSession> verifyLoginCode({
    required String email,
    required String code,
  }) async {
    _requireConfigured();
    AccountBackendError? lastError;
    for (final verificationType in const ['email', 'magiclink']) {
      try {
        final json = await _postJson(
          _config.authUri('verify'),
          {
            'email': email.trim(),
            'token': code.trim(),
            'type': verificationType,
          },
          includeAuth: false,
        );
        final session = AccountBackendSession.fromJson(json);
        if (session.accessToken.isEmpty) {
          throw const AccountBackendError(
            'missing_access_token',
            'Login succeeded but no access token was returned.',
          );
        }
        return session;
      } on AccountBackendError catch (error) {
        lastError = error;
        if (!_canTryMagicLinkFallback(error)) rethrow;
      }
    }
    throw lastError ??
        const AccountBackendError(
          'verification_failed',
          'Verification failed.',
        );
  }

  bool _canTryMagicLinkFallback(AccountBackendError error) {
    if (error.statusCode == null) return false;
    if (error.statusCode! < 400 || error.statusCode! >= 500) return false;
    final text = '${error.code} ${error.message}'.toLowerCase();
    return text.contains('invalid') ||
        text.contains('expired') ||
        text.contains('otp') ||
        text.contains('token');
  }

  Future<AccountBackendProfile> getAccountProfile(String accessToken) async {
    final json = await _callFunction(
      'get-account-profile',
      accessToken: accessToken,
    );
    return AccountBackendProfile.fromJson(json);
  }

  Future<AccountBackendProfile> refreshSession({
    required String accessToken,
    required String deviceId,
    String? friendlyName,
  }) async {
    final json = await _callFunction(
      'refresh-session',
      accessToken: accessToken,
      body: {
        'deviceId': deviceId,
        if (friendlyName != null) 'friendlyName': friendlyName,
      },
    );
    return AccountBackendProfile.fromJson(json);
  }

  Future<void> logout({
    required String accessToken,
    required String deviceId,
  }) async {
    await _callFunction(
      'logout-session',
      accessToken: accessToken,
      body: {'deviceId': deviceId},
    );
  }

  Future<AccountBackendSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    _requireConfigured();
    final json = await _postJson(
      _config.authUri('token').replace(query: 'grant_type=password'),
      {
        'email': email.trim(),
        'password': password,
      },
      includeAuth: false,
    );
    final session = AccountBackendSession.fromJson(json);
    if (session.accessToken.isEmpty) {
      throw const AccountBackendError(
        'missing_access_token',
        'Password sign-in succeeded but no access token was returned.',
      );
    }
    return session;
  }

  Future<AccountBackendSession> refreshAccessToken({
    required String refreshToken,
  }) async {
    _requireConfigured();
    final json = await _postJson(
      _config.authUri('token').replace(query: 'grant_type=refresh_token'),
      {'refresh_token': refreshToken},
      includeAuth: false,
    );
    final session = AccountBackendSession.fromJson(json);
    if (session.accessToken.isEmpty) {
      throw const AccountBackendError(
        'missing_access_token',
        'Session refresh succeeded but no access token was returned.',
      );
    }
    return session;
  }

  Future<void> setPassword({
    required String accessToken,
    required String password,
  }) async {
    _requireConfigured();
    await _putJson(
      _config.authUri('user'),
      {'password': password},
      bearerToken: accessToken,
    );
  }

  Future<void> requestPasswordResetCode(String email) async {
    _requireConfigured();
    await _postJson(
      _config.authUri('recover'),
      {'email': email.trim()},
      includeAuth: false,
    );
  }

  Future<AccountBackendSession> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    _requireConfigured();
    final json = await _postJson(
      _config.authUri('verify'),
      {
        'email': email.trim(),
        'token': code.trim(),
        'type': 'recovery',
      },
      includeAuth: false,
    );
    final session = AccountBackendSession.fromJson(json);
    if (session.accessToken.isEmpty) {
      throw const AccountBackendError(
        'missing_access_token',
        'Password reset was verified but no access token was returned.',
      );
    }
    return session;
  }

  Future<void> updateEmail({
    required String accessToken,
    required String newEmail,
  }) async {
    _requireConfigured();
    await _putJson(
      _config.authUri('user'),
      {'email': newEmail.trim()},
      bearerToken: accessToken,
    );
  }

  Future<AccountBackendRole> redeemLicenseCode({
    required String accessToken,
    required String code,
  }) async {
    final json = await _callFunction(
      'redeem-license-code',
      accessToken: accessToken,
      body: {'code': code.trim()},
    );
    return AccountBackendRole.fromWire(json['role']);
  }

  Future<void> revokeCurrentDevice({
    required String accessToken,
    required String deviceId,
  }) async {
    await _callFunction(
      'revoke-current-device',
      accessToken: accessToken,
      body: {'deviceId': deviceId},
    );
  }

  Future<void> submitFeedback(Map<String, Object?> report) async {
    _requireConfigured();
    await _postJson(
      _config.functionUri('submit-feedback'),
      report,
      includeAuth: false,
    );
  }

  Future<void> submitFeedbackPayload(String payload) async {
    _requireConfigured();
    final request = await _client
        .postUrl(_config.functionUri('submit-feedback'))
        .timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set('apikey', _config.anonKey.trim());
    request.write(payload);
    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'feedback_proxy_error';
      var message = code;
      try {
        final decoded = jsonDecode(text) as Map<String, dynamic>;
        code = decoded['error']?.toString() ?? code;
        message = decoded['message']?.toString() ?? code;
      } catch (_) {
        if (text.trim().isNotEmpty) message = text.trim();
      }
      throw AccountBackendError(code, message, statusCode: response.statusCode);
    }
  }

  Future<Map<String, dynamic>> _callFunction(
    String functionName, {
    required String accessToken,
    Map<String, Object?> body = const {},
  }) {
    _requireConfigured();
    return _postJson(
      _config.functionUri(functionName),
      body,
      bearerToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, Object?> body, {
    String? bearerToken,
    bool includeAuth = true,
  }) async {
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set('apikey', _config.anonKey.trim());
    if (includeAuth && bearerToken != null && bearerToken.trim().isNotEmpty) {
      request.headers.set('Authorization', 'Bearer ${bearerToken.trim()}');
    } else if (!includeAuth) {
      request.headers.set('Authorization', 'Bearer ${_config.anonKey.trim()}');
    }
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    final decoded = _decodeJsonObject(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwBackendError(response.statusCode, decoded, text);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _putJson(
    Uri uri,
    Map<String, Object?> body, {
    required String bearerToken,
  }) async {
    final request = await _client.putUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set('apikey', _config.anonKey.trim());
    request.headers.set('Authorization', 'Bearer ${bearerToken.trim()}');
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    final text = await utf8.decoder.bind(response).join().timeout(timeout);
    final decoded = _decodeJsonObject(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwBackendError(response.statusCode, decoded, text);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeJsonObject(String text) {
    if (text.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{'msg': text.trim()};
    }
    return <String, dynamic>{'msg': text.trim()};
  }

  Never _throwBackendError(
    int statusCode,
    Map<String, dynamic> decoded,
    String rawText,
  ) {
    final code = (decoded['error_code'] ??
            decoded['code'] ??
            decoded['error'] ??
            'backend_error')
        .toString();
    final rawMessage = rawText.trim();
    final message = (decoded['msg'] ??
            decoded['message'] ??
            decoded['error_description'] ??
            (rawMessage.isEmpty ? code : rawMessage))
        .toString();
    throw AccountBackendError(
      code,
      'HTTP $statusCode: $code - $message',
      statusCode: statusCode,
    );
  }

  void _requireConfigured() {
    if (!_config.isConfigured) {
      throw const AccountBackendError(
        'backend_not_configured',
        'Account backend is not configured for this build.',
      );
    }
  }
}
