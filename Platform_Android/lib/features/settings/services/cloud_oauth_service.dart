import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/security/encrypted_file_store.dart';
import 'cloud_connection_store.dart';

const googleDriveOAuthClientId =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID');
const dropboxOAuthClientId = String.fromEnvironment('DROPBOX_CLIENT_ID');

/// Android has no equivalent to Windows' localhost-loopback OAuth callback
/// server - Google's "Android" OAuth client type validates redirects via the
/// app's package name + signing certificate, not an arbitrary registered
/// redirect URI, so the standard (and Google-documented) pattern for a
/// generic/AppAuth-style flow is a custom-scheme deep link instead. Both
/// redirect URIs below must match the intent-filters declared in
/// AndroidManifest.xml.
String _googleDriveOAuthRedirectUri(String clientId) {
  final reversed = clientId.replaceAll('.apps.googleusercontent.com', '');
  return 'com.googleusercontent.apps.$reversed:/oauth2redirect';
}

const String _dropboxOAuthRedirectUri = 'autoteleprompter://oauth2redirect';

String _cleanOAuthClientId(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim();
}

bool _looksLikeGoogleOAuthClientId(String value) {
  return RegExp(r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$')
      .hasMatch(value);
}

class CloudAccountInfo {
  final String providerId;
  final String providerLabel;
  final String accountLabel;
  final String connectedAtIso;
  final String? expiresAtIso;

  const CloudAccountInfo({
    required this.providerId,
    required this.providerLabel,
    required this.accountLabel,
    required this.connectedAtIso,
    this.expiresAtIso,
  });

  Map<String, Object?> toJson() => {
        'providerId': providerId,
        'providerLabel': providerLabel,
        'accountLabel': accountLabel,
        'connectedAtIso': connectedAtIso,
        if (expiresAtIso != null) 'expiresAtIso': expiresAtIso,
      };

  static CloudAccountInfo? fromJson(Map<String, dynamic> json) {
    final providerId = json['providerId']?.toString() ?? '';
    final providerLabel = json['providerLabel']?.toString() ?? '';
    final accountLabel = json['accountLabel']?.toString() ?? '';
    final connectedAtIso = json['connectedAtIso']?.toString() ?? '';
    if (providerId.isEmpty ||
        providerLabel.isEmpty ||
        accountLabel.isEmpty ||
        connectedAtIso.isEmpty) {
      return null;
    }
    return CloudAccountInfo(
      providerId: providerId,
      providerLabel: providerLabel,
      accountLabel: accountLabel,
      connectedAtIso: connectedAtIso,
      expiresAtIso: json['expiresAtIso']?.toString(),
    );
  }
}

class CloudAuthorizedSession {
  final CloudAccountInfo account;
  final String accessToken;

  const CloudAuthorizedSession({
    required this.account,
    required this.accessToken,
  });
}

class CloudAccountConnectResult {
  final bool connected;
  final bool missingCredentials;
  final bool unsupported;
  final String message;
  final CloudAccountInfo? account;

  const CloudAccountConnectResult({
    required this.connected,
    required this.message,
    this.account,
    this.missingCredentials = false,
    this.unsupported = false,
  });
}

class CloudOAuthService {
  static const String _collection = 'cloud_accounts';
  static const String _extension = 'json';
  static const String _kind = 'cloud-oauth-token';
  static const Duration _authTimeout = Duration(minutes: 3);

  CloudOAuthService({
    EncryptedFileStore? encryptedStore,
    HttpClient? httpClient,
    AppLinks? appLinks,
  })  : _encryptedStore = encryptedStore ?? EncryptedFileStore(),
        _httpClient = httpClient ?? HttpClient(),
        _appLinks = appLinks ?? AppLinks();

  final EncryptedFileStore _encryptedStore;
  final HttpClient _httpClient;
  final AppLinks _appLinks;

  Future<Map<String, CloudAccountInfo>> loadAccounts() async {
    final result = <String, CloudAccountInfo>{};
    for (final provider in CloudConnectionStore.providers) {
      final account = await loadAccount(provider.id);
      if (account != null) result[provider.id] = account;
    }
    return result;
  }

  Future<CloudAccountInfo?> loadAccount(String providerId) async {
    final decoded = await _loadEncryptedAccountPayload(providerId);
    if (decoded == null) return null;
    final accountJson = decoded['account'];
    if (accountJson is! Map<String, dynamic>) return null;
    return CloudAccountInfo.fromJson(accountJson);
  }

  Future<CloudAuthorizedSession?> authorizeAccount(String providerId) async {
    final decoded = await _loadEncryptedAccountPayload(providerId);
    if (decoded == null) return null;
    final accountJson = decoded['account'];
    final tokenJson = decoded['token'];
    if (accountJson is! Map<String, dynamic> ||
        tokenJson is! Map<String, dynamic>) {
      return null;
    }
    var account = CloudAccountInfo.fromJson(accountJson);
    if (account == null) return null;
    var tokenPayload = Map<String, dynamic>.from(tokenJson);
    if (_shouldRefreshToken(account, tokenPayload)) {
      final provider = CloudConnectionStore.providers.firstWhere(
        (item) => item.id == providerId,
        orElse: () => CloudProviderDefinition(
          id: providerId,
          label: providerId,
          subtitle: '',
        ),
      );
      final config = _oauthConfigFor(provider);
      if (config != null && config.clientId.trim().isNotEmpty) {
        tokenPayload = await _refreshToken(
          config: config,
          refreshToken: tokenPayload['refresh_token'].toString(),
          previousPayload: tokenPayload,
        );
        account = CloudAccountInfo(
          providerId: account.providerId,
          providerLabel: account.providerLabel,
          accountLabel: account.accountLabel,
          connectedAtIso: account.connectedAtIso,
          expiresAtIso: _expiresAtIso(tokenPayload),
        );
        await _saveEncryptedAccount(providerId, account, tokenPayload);
      }
    }
    final accessToken = tokenPayload['access_token']?.toString() ?? '';
    if (accessToken.isEmpty) return null;
    return CloudAuthorizedSession(account: account, accessToken: accessToken);
  }

  Future<Map<String, dynamic>?> _loadEncryptedAccountPayload(
    String providerId,
  ) async {
    final file = await _encryptedStore.fileFor(
      collection: _collection,
      id: providerId,
      extension: _extension,
    );
    if (file == null) return null;
    final bytes = await _encryptedStore.readBytes(file, kind: _kind);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  Future<void> disconnect(String providerId) {
    return _encryptedStore.delete(
      collection: _collection,
      id: providerId,
      extension: _extension,
    );
  }

  Future<CloudAccountConnectResult> connect(
    CloudProviderDefinition provider,
  ) async {
    final config = _oauthConfigFor(provider);
    if (config == null) {
      return CloudAccountConnectResult(
        connected: false,
        unsupported: true,
        message:
            '${provider.label} direct account sign-in is not available in this '
            'Android app yet. Use Local Backup for now.',
      );
    }
    if (config.clientId.trim().isEmpty) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: true,
        message: '${provider.label} account sign-in is ready in code, but this '
            'installation is missing ${config.clientIdDefineName}.',
      );
    }
    final credentialIssue = config.credentialIssue;
    if (credentialIssue != null) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: true,
        message: credentialIssue,
      );
    }

    StreamSubscription<Uri>? subscription;
    try {
      final redirectUri = config.redirectUri;
      final state = _randomBase64Url(24);
      final verifier = _randomBase64Url(64);
      final challenge = _pkceChallenge(verifier);
      final callbackFuture = _waitForOAuthCallback(
        redirectUri: redirectUri,
        expectedState: state,
        subscribe: (sub) => subscription = sub,
      );

      final launched = await launchUrl(
        config.authorizationUri(
          redirectUri: redirectUri,
          state: state,
          challenge: challenge,
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return CloudAccountConnectResult(
          connected: false,
          message: '${provider.label} sign-in could not open a browser.',
        );
      }

      final callback = await callbackFuture.timeout(_authTimeout);
      if (callback.error != null) {
        return CloudAccountConnectResult(
          connected: false,
          message: '${provider.label} sign-in was rejected: ${callback.error}.',
        );
      }
      final code = callback.code;
      if (code == null || code.isEmpty) {
        return CloudAccountConnectResult(
          connected: false,
          message: '${provider.label} did not return an authorization code.',
        );
      }

      final tokenPayload = await _exchangeCode(
        config: config,
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
      final accessToken = tokenPayload['access_token']?.toString() ?? '';
      if (accessToken.isEmpty) {
        return CloudAccountConnectResult(
          connected: false,
          message: '${provider.label} token response did not include access.',
        );
      }

      final accountLabel = await config.accountLabel(_httpClient, accessToken);
      final account = CloudAccountInfo(
        providerId: provider.id,
        providerLabel: provider.label,
        accountLabel: accountLabel,
        connectedAtIso: DateTime.now().toUtc().toIso8601String(),
        expiresAtIso: _expiresAtIso(tokenPayload),
      );
      await _saveEncryptedAccount(provider.id, account, tokenPayload);
      return CloudAccountConnectResult(
        connected: true,
        account: account,
        message: '${provider.label} connected as $accountLabel.',
      );
    } on TimeoutException {
      return CloudAccountConnectResult(
        connected: false,
        message: '${provider.label} sign-in timed out.',
      );
    } on _CloudOAuthTokenException catch (error) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: error.isCredentialConfigurationIssue,
        message: error.message,
      );
    } catch (error) {
      return CloudAccountConnectResult(
        connected: false,
        message: '${provider.label} sign-in failed: $error',
      );
    } finally {
      unawaited(subscription?.cancel());
    }
  }

  Future<void> _saveEncryptedAccount(
    String providerId,
    CloudAccountInfo account,
    Map<String, dynamic> tokenPayload,
  ) async {
    final payload = jsonEncode({
      'schemaVersion': 1,
      'account': account.toJson(),
      'token': tokenPayload,
    });
    await _encryptedStore.writeBytes(
      collection: _collection,
      id: providerId,
      extension: _extension,
      kind: _kind,
      bytes: utf8.encode(payload),
    );
  }

  /// Waits for the system browser to redirect back into the app via the
  /// custom-scheme intent-filter declared in AndroidManifest.xml. Unlike
  /// Windows' loopback HTTP server, there is nothing listening on a port -
  /// the OS delivers the redirect as a new Intent, which `app_links`
  /// surfaces as a `Uri` on `uriLinkStream`.
  Future<_OAuthCallback> _waitForOAuthCallback({
    required String redirectUri,
    required String expectedState,
    required void Function(StreamSubscription<Uri>) subscribe,
  }) {
    final completer = Completer<_OAuthCallback>();
    final expectedPrefix = redirectUri.split('?').first;
    late StreamSubscription<Uri> subscription;
    subscription = _appLinks.uriLinkStream.listen((uri) {
      final received = uri.toString().split('?').first;
      if (received != expectedPrefix) return;
      final state = uri.queryParameters['state'];
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];
      if (state != expectedState) {
        if (!completer.isCompleted) {
          completer.complete(
            const _OAuthCallback(error: 'security_state_mismatch'),
          );
        }
      } else if (!completer.isCompleted) {
        completer.complete(_OAuthCallback(code: code, error: error));
      }
      subscription.cancel();
    });
    subscribe(subscription);
    return completer.future;
  }

  Future<Map<String, dynamic>> _exchangeCode({
    required _OAuthProviderConfig config,
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    return _postTokenRequest(
      config: config,
      parameters: {
        'grant_type': 'authorization_code',
        'client_id': config.clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
      },
    );
  }

  Future<Map<String, dynamic>> _postTokenRequest({
    required _OAuthProviderConfig config,
    required Map<String, String> parameters,
  }) async {
    final request = await _httpClient.postUrl(config.tokenEndpoint);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    final payload = <String, String>{
      ...parameters,
    };
    request.write(Uri(queryParameters: payload).query);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _CloudOAuthTokenException.fromTokenResponse(
        config: config,
        statusCode: response.statusCode,
        body: body,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('token exchange returned invalid JSON');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _refreshToken({
    required _OAuthProviderConfig config,
    required String refreshToken,
    required Map<String, dynamic> previousPayload,
  }) async {
    final parameters = <String, String>{
      'grant_type': 'refresh_token',
      'client_id': config.clientId,
      'refresh_token': refreshToken,
    };
    final decoded = await _postTokenRequest(
      config: config,
      parameters: parameters,
    );
    return {
      ...previousPayload,
      ...decoded,
      'refresh_token': decoded['refresh_token'] ?? refreshToken,
    };
  }

  String _randomBase64Url(int bytes) {
    final random = Random.secure();
    final values = List<int>.generate(bytes, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  String _pkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String? _expiresAtIso(Map<String, dynamic> tokenPayload) {
    final expiresIn = tokenPayload['expires_in'];
    if (expiresIn is! int || expiresIn <= 0) return null;
    return DateTime.now()
        .toUtc()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();
  }

  bool _tokenExpired(CloudAccountInfo account) {
    final raw = account.expiresAtIso;
    if (raw == null || raw.isEmpty) return false;
    final expiresAt = DateTime.tryParse(raw);
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(
          expiresAt.subtract(const Duration(minutes: 2)),
        );
  }

  bool _shouldRefreshToken(
    CloudAccountInfo account,
    Map<String, dynamic> tokenPayload,
  ) {
    if (tokenPayload['refresh_token'] == null) return false;
    final raw = account.expiresAtIso;
    if (raw == null || raw.isEmpty) return true;
    return _tokenExpired(account);
  }

  _OAuthProviderConfig? _oauthConfigFor(CloudProviderDefinition provider) {
    return switch (provider.id) {
      CloudConnectionStore.googleDrive => _OAuthProviderConfig.googleDrive(
          clientId: googleDriveOAuthClientId,
        ),
      CloudConnectionStore.dropbox => _OAuthProviderConfig.dropbox(
          clientId: dropboxOAuthClientId,
        ),
      _ => null,
    };
  }
}

class _CloudOAuthTokenException implements Exception {
  final String message;
  final bool isCredentialConfigurationIssue;

  const _CloudOAuthTokenException(
    this.message, {
    this.isCredentialConfigurationIssue = false,
  });

  factory _CloudOAuthTokenException.fromTokenResponse({
    required _OAuthProviderConfig config,
    required int statusCode,
    required String body,
  }) {
    final lower = body.toLowerCase();
    if (config.clientIdDefineName == 'GOOGLE_DRIVE_CLIENT_ID' &&
        lower.contains('invalid_client')) {
      return const _CloudOAuthTokenException(
        'Google Drive rejected the Android OAuth credentials. Verify the '
        'GOOGLE_DRIVE_CLIENT_ID, the app package name, and the signing '
        'certificate SHA-1 registered in Google Cloud Console.',
        isCredentialConfigurationIssue: true,
      );
    }
    return _CloudOAuthTokenException(
      'Token exchange failed ($statusCode): $body',
    );
  }

  @override
  String toString() => message;
}

class _OAuthCallback {
  final String? code;
  final String? error;

  const _OAuthCallback({this.code, this.error});
}

class _OAuthProviderConfig {
  final String clientId;
  final String clientIdDefineName;
  final String redirectUri;
  final Uri tokenEndpoint;
  final Uri Function({
    required String redirectUri,
    required String state,
    required String challenge,
  }) authorizationUri;
  final Future<String> Function(HttpClient client, String accessToken)
      accountLabel;

  const _OAuthProviderConfig({
    required this.clientId,
    required this.clientIdDefineName,
    required this.redirectUri,
    required this.tokenEndpoint,
    required this.authorizationUri,
    required this.accountLabel,
  });

  String? get credentialIssue {
    if (clientIdDefineName == 'GOOGLE_DRIVE_CLIENT_ID' &&
        !_looksLikeGoogleOAuthClientId(clientId)) {
      return 'Google Drive account sign-in is ready in code, but '
          'GOOGLE_DRIVE_CLIENT_ID is not a valid OAuth Android app Client ID.';
    }
    return null;
  }

  factory _OAuthProviderConfig.googleDrive({required String clientId}) {
    final normalizedClientId = _cleanOAuthClientId(clientId);
    return _OAuthProviderConfig(
      clientId: normalizedClientId,
      clientIdDefineName: 'GOOGLE_DRIVE_CLIENT_ID',
      redirectUri: _googleDriveOAuthRedirectUri(normalizedClientId),
      tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
      authorizationUri: ({
        required String redirectUri,
        required String state,
        required String challenge,
      }) =>
          Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': normalizedClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile '
            'https://www.googleapis.com/auth/drive.file',
        'access_type': 'offline',
        'prompt': 'consent',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }),
      accountLabel: _googleAccountLabel,
    );
  }

  factory _OAuthProviderConfig.dropbox({required String clientId}) {
    final normalizedClientId = _cleanOAuthClientId(clientId);
    return _OAuthProviderConfig(
      clientId: normalizedClientId,
      clientIdDefineName: 'DROPBOX_CLIENT_ID',
      redirectUri: _dropboxOAuthRedirectUri,
      tokenEndpoint: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      authorizationUri: ({
        required String redirectUri,
        required String state,
        required String challenge,
      }) =>
          Uri.https('www.dropbox.com', '/oauth2/authorize', {
        'client_id': normalizedClientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'token_access_type': 'offline',
        'scope': 'account_info.read files.metadata.read '
            'files.content.read files.content.write',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      }),
      accountLabel: _dropboxAccountLabel,
    );
  }

  static Future<String> _googleAccountLabel(
    HttpClient client,
    String accessToken,
  ) async {
    final request = await client.getUrl(
      Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google account lookup failed (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return 'Google Drive account';
    return decoded['email']?.toString().trim().isNotEmpty == true
        ? decoded['email'].toString()
        : decoded['name']?.toString() ?? 'Google Drive account';
  }

  static Future<String> _dropboxAccountLabel(
    HttpClient client,
    String accessToken,
  ) async {
    final request = await client.postUrl(
      Uri.parse('https://api.dropboxapi.com/2/users/get_current_account'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
    request.headers.contentType = ContentType.json;
    request.write('null');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          'Dropbox account lookup failed (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return 'Dropbox account';
    final email = decoded['email']?.toString();
    if (email != null && email.trim().isNotEmpty) return email;
    final name = decoded['name'];
    if (name is Map<String, dynamic>) {
      return name['display_name']?.toString() ?? 'Dropbox account';
    }
    return 'Dropbox account';
  }
}
