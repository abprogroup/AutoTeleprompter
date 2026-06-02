import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../core/security/encrypted_file_store.dart';
import 'cloud_connection_store.dart';

const googleDriveOAuthClientId =
    String.fromEnvironment('GOOGLE_DRIVE_CLIENT_ID');
const dropboxOAuthClientId = String.fromEnvironment('DROPBOX_CLIENT_ID');

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
  })  : _encryptedStore = encryptedStore ?? EncryptedFileStore(),
        _httpClient = httpClient ?? HttpClient();

  final EncryptedFileStore _encryptedStore;
  final HttpClient _httpClient;

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
    if (_tokenExpired(account) && tokenPayload['refresh_token'] != null) {
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
            'Windows beta. Use the local synced folder for now.',
      );
    }
    if (config.clientId.trim().isEmpty) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: true,
        message: '${provider.label} account sign-in is ready in code, but this '
            'build is missing ${config.clientIdDefineName}.',
      );
    }

    HttpServer? callbackServer;
    try {
      callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirectUri =
          'http://127.0.0.1:${callbackServer.port}/oauth/callback';
      final state = _randomBase64Url(24);
      final verifier = _randomBase64Url(64);
      final challenge = _pkceChallenge(verifier);
      final callbackFuture = _waitForOAuthCallback(callbackServer, state);

      await _openBrowser(
        config.authorizationUri(
          redirectUri: redirectUri,
          state: state,
          challenge: challenge,
        ),
      );

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
    } catch (error) {
      return CloudAccountConnectResult(
        connected: false,
        message: '${provider.label} sign-in failed: $error',
      );
    } finally {
      unawaited(callbackServer?.close(force: true));
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

  Future<Map<String, dynamic>> _exchangeCode({
    required _OAuthProviderConfig config,
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final request = await _httpClient.postUrl(config.tokenEndpoint);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: {
      'grant_type': 'authorization_code',
      'client_id': config.clientId,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
    }).query);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('token exchange failed (${response.statusCode}): $body');
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
    final request = await _httpClient.postUrl(config.tokenEndpoint);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: {
      'grant_type': 'refresh_token',
      'client_id': config.clientId,
      'refresh_token': refreshToken,
    }).query);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('token refresh failed (${response.statusCode}): $body');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('token refresh returned invalid JSON');
    }
    return {
      ...previousPayload,
      ...decoded,
      'refresh_token': decoded['refresh_token'] ?? refreshToken,
    };
  }

  Future<_OAuthCallback> _waitForOAuthCallback(
    HttpServer server,
    String expectedState,
  ) {
    final completer = Completer<_OAuthCallback>();
    late StreamSubscription<HttpRequest> subscription;
    subscription = server.listen((request) async {
      if (request.uri.path != '/oauth/callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final state = request.uri.queryParameters['state'];
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];
      final ok = state == expectedState;
      request.response.headers.contentType = ContentType.html;
      request.response.write(ok
          ? '<html><body><h2>AutoTeleprompter connected.</h2>'
              '<p>You can close this browser tab.</p></body></html>'
          : '<html><body><h2>AutoTeleprompter sign-in rejected.</h2>'
              '<p>Security state did not match.</p></body></html>');
      await request.response.close();
      if (!ok) {
        completer.complete(
          const _OAuthCallback(error: 'security_state_mismatch'),
        );
      } else {
        completer.complete(_OAuthCallback(code: code, error: error));
      }
      await subscription.cancel();
    });
    return completer.future;
  }

  Future<void> _openBrowser(Uri uri) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', uri.toString()]);
    } else {
      await Process.run('open', [uri.toString()]);
    }
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

class _OAuthCallback {
  final String? code;
  final String? error;

  const _OAuthCallback({this.code, this.error});
}

class _OAuthProviderConfig {
  final String clientId;
  final String clientIdDefineName;
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
    required this.tokenEndpoint,
    required this.authorizationUri,
    required this.accountLabel,
  });

  factory _OAuthProviderConfig.googleDrive({required String clientId}) {
    return _OAuthProviderConfig(
      clientId: clientId,
      clientIdDefineName: 'GOOGLE_DRIVE_CLIENT_ID',
      tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
      authorizationUri: ({
        required String redirectUri,
        required String state,
        required String challenge,
      }) =>
          Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
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
    return _OAuthProviderConfig(
      clientId: clientId,
      clientIdDefineName: 'DROPBOX_CLIENT_ID',
      tokenEndpoint: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      authorizationUri: ({
        required String redirectUri,
        required String state,
        required String challenge,
      }) =>
          Uri.https('www.dropbox.com', '/oauth2/authorize', {
        'client_id': clientId,
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
