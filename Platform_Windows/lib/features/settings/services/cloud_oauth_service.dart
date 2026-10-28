import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/connection_retry_gate.dart';

import '../../../core/security/encrypted_file_store.dart';
import 'cloud_connection_store.dart';
import 'cloud_sign_in_runtime.dart';

part 'cloud_oauth_service.providers.dart';
part 'cloud_oauth_service.renewal.dart';
part 'cloud_oauth_service.sign_in.dart';

const googleDriveOAuthClientId = String.fromEnvironment(
  'GOOGLE_DRIVE_CLIENT_ID',
);
const googleDriveOAuthClientSecret = String.fromEnvironment(
  'GOOGLE_DRIVE_CLIENT_SECRET',
);
const dropboxOAuthClientId = String.fromEnvironment('DROPBOX_CLIENT_ID');
const cloudOAuthRedirectPort = int.fromEnvironment(
  'CLOUD_OAUTH_REDIRECT_PORT',
  defaultValue: 51747,
);

String _cleanOAuthClientId(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim();
}

bool _looksLikeGoogleOAuthClientId(String value) {
  return RegExp(
    r'^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$',
  ).hasMatch(value);
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

  factory CloudOAuthService({
    EncryptedFileStore? encryptedStore,
    HttpClient? httpClient,
    CloudOAuthCredentials? credentials,
    DateTime Function()? now,
    Duration? requestTimeout,
    CloudSignInRuntime? signInRuntime,
  }) {
    if (encryptedStore == null &&
        httpClient == null &&
        credentials == null &&
        now == null &&
        requestTimeout == null &&
        signInRuntime == null) {
      return _shared;
    }
    return CloudOAuthService._(
      encryptedStore: encryptedStore,
      httpClient: httpClient,
      credentials: credentials,
      now: now,
      requestTimeout: requestTimeout,
      signInRuntime: signInRuntime,
    );
  }

  CloudOAuthService._({
    EncryptedFileStore? encryptedStore,
    HttpClient? httpClient,
    CloudOAuthCredentials? credentials,
    DateTime Function()? now,
    Duration? requestTimeout,
    CloudSignInRuntime? signInRuntime,
  }) : _encryptedStore = encryptedStore ?? EncryptedFileStore(),
       _httpClient =
           httpClient ??
           (HttpClient()
             ..connectionTimeout =
                 (requestTimeout ?? const Duration(seconds: 15))),
       _credentials = credentials ?? const CloudOAuthCredentials(),
       _now = now ?? DateTime.now,
       _requestTimeout = requestTimeout ?? const Duration(seconds: 15),
       _signInRuntime = signInRuntime ?? const CloudSignInRuntime();

  static final _shared = CloudOAuthService._();
  final EncryptedFileStore _encryptedStore;
  final HttpClient _httpClient;
  final CloudOAuthCredentials _credentials;
  final DateTime Function() _now;
  final Duration _requestTimeout;
  final CloudSignInRuntime _signInRuntime;
  final activeSignIn = ValueNotifier<String?>(null);
  _CloudSignInAttempt? _signInAttempt;
  final _pending = <String, Future<CloudAuthorizedSession?>>{};
  final _epochs = <String, int>{};
  final _storageOperations = <String, Future<void>>{};
  final _retry = <String, ConnectionRetryGate>{};
  final connectionStates = ValueNotifier<Map<String, CloudConnectionStatus>>(
    {},
  );
  final _states = <String, CloudConnectionStatus>{};

  Future<Map<String, CloudAccountInfo>> loadAccounts() async {
    final result = <String, CloudAccountInfo>{};
    for (final provider in CloudConnectionStore.providers) {
      final account = await loadAccount(provider.id);
      if (account != null) result[provider.id] = account;
    }
    return result;
  }

  Future<CloudAccountInfo?> loadAccount(String providerId) async {
    final epoch = _epochs[providerId] ?? 0;
    final decoded = await _loadEncryptedAccountPayload(providerId);
    if ((_epochs[providerId] ?? 0) != epoch) return null;
    if (decoded == null) return null;
    final accountJson = decoded['account'];
    if (accountJson is! Map<String, dynamic>) return null;
    return CloudAccountInfo.fromJson(accountJson);
  }

  Future<CloudAuthorizedSession?> authorizeAccount(String providerId) =>
      _authorizeWithRenewal(providerId);

  /// Credential maintenance only. Never lists, uploads or deletes cloud files.
  Future<void> maintainConnections() async {
    await Future.wait(
      CloudConnectionStore.providers.map((provider) async {
        try {
          await authorizeAccount(provider.id);
        } catch (_) {
          // Status and bounded retry are owned by the renewal operation.
        }
      }),
    );
  }

  Future<Map<String, dynamic>?> _loadEncryptedAccountPayload(
    String providerId,
  ) => _serializeAccountStorage<Map<String, dynamic>?>(providerId, () async {
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
  });

  Future<void> disconnect(String providerId) async {
    if (activeSignIn.value == providerId) cancelSignIn();
    _epochs[providerId] = (_epochs[providerId] ?? 0) + 1;
    _pending.remove(providerId);
    await _serializeAccountStorage(
      providerId,
      () => _encryptedStore.delete(
        collection: _collection,
        id: providerId,
        extension: _extension,
      ),
    );
    _retry.remove(providerId);
    _setConnectionStatus(providerId, CloudConnectionStatus.disconnected);
  }

  Future<CloudAccountConnectResult> connect(CloudProviderDefinition provider) =>
      _connectAccount(provider);

  void cancelSignIn() => _signInAttempt?.cancel();

  Future<CloudAccountConnectResult> checkConnection(
    CloudProviderDefinition provider,
  ) => _checkAccountConnection(provider);

  Future<void> _saveEncryptedAccount(
    String providerId,
    CloudAccountInfo account,
    Map<String, dynamic> tokenPayload, {
    required int epoch,
  }) async {
    final payload = jsonEncode({
      'schemaVersion': 1,
      'account': account.toJson(),
      'token': tokenPayload,
    });
    await _serializeAccountStorage(providerId, () async {
      if ((_epochs[providerId] ?? 0) != epoch) {
        throw const CloudConnectionException('Connection changed.');
      }
      await _encryptedStore.writeBytes(
        collection: _collection,
        id: providerId,
        extension: _extension,
        kind: _kind,
        bytes: utf8.encode(payload),
      );
    });
  }

  Future<HttpServer> _bindOAuthCallbackServer(
    _OAuthProviderConfig config,
  ) async {
    const firstPort = cloudOAuthRedirectPort;
    final lastPort =
        config.allowDynamicLoopbackPort ? firstPort + 20 : firstPort;
    SocketException? lastError;
    for (var port = firstPort; port <= lastPort; port++) {
      try {
        return await _signInRuntime.bindServer(port);
      } on SocketException catch (error) {
        if (error.osError?.errorCode != 10048 &&
            error.osError?.errorCode != 98 &&
            error.osError?.errorCode != 48) {
          rethrow;
        }
        lastError = error;
      }
    }
    throw lastError ??
        const SocketException('No cloud OAuth callback port available.');
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
    final request = await _httpClient
        .postUrl(config.tokenEndpoint)
        .timeout(_requestTimeout);
    request.followRedirects = false;
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    final payload = <String, String>{...parameters};
    request.write(Uri(queryParameters: payload).query);
    final response = await request.close().timeout(
      _requestTimeout,
      onTimeout: () {
        request.abort();
        throw TimeoutException('Cloud renewal timed out.');
      },
    );
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(
          _requestTimeout,
          onTimeout: () {
            request.abort();
            throw TimeoutException('Cloud renewal timed out.');
          },
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (config.shouldRetryWithClientSecret(
        parameters: parameters,
        responseBody: body,
      )) {
        return _postTokenRequest(
          config: config,
          parameters: {...parameters, 'client_secret': config.clientSecret!},
        );
      }
      throw _CloudOAuthTokenException.fromTokenResponse(
        config: config,
        statusCode: response.statusCode,
        body: body,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CloudConnectionException(
        'Cloud renewal returned invalid data.',
      );
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
    if ((decoded['access_token']?.toString().trim().isEmpty ?? true) ||
        decoded['expires_in'] is! num ||
        (decoded['expires_in'] as num) <= 0) {
      throw const CloudConnectionException(
        'Cloud renewal returned incomplete credentials.',
      );
    }
    return {
      ...previousPayload,
      ...decoded,
      'refresh_token':
          (decoded['refresh_token']?.toString().isNotEmpty ?? false)
              ? decoded['refresh_token']
              : refreshToken,
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
    if (expiresIn is! num || expiresIn <= 0) return null;
    return _now()
        .toUtc()
        .add(Duration(seconds: expiresIn.toInt()))
        .toIso8601String();
  }

  bool _tokenExpired(CloudAccountInfo account) {
    final raw = account.expiresAtIso;
    if (raw == null || raw.isEmpty) return true;
    final expiresAt = DateTime.tryParse(raw);
    if (expiresAt == null) return true;
    return !_now().toUtc().isBefore(
      expiresAt.subtract(const Duration(minutes: 2)),
    );
  }

  _OAuthProviderConfig? _oauthConfigFor(CloudProviderDefinition provider) {
    return switch (provider.id) {
      CloudConnectionStore.googleDrive => _OAuthProviderConfig.googleDrive(
        clientId: _credentials.googleClientId,
        clientSecret: _credentials.googleClientSecret,
      ),
      CloudConnectionStore.dropbox => _OAuthProviderConfig.dropbox(
        clientId: _credentials.dropboxClientId,
      ),
      _ => null,
    };
  }
}
