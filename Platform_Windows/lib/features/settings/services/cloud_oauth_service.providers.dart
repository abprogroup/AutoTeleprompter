part of 'cloud_oauth_service.dart';

class _CloudOAuthTokenException extends CloudConnectionException {
  final bool isCredentialConfigurationIssue;

  const _CloudOAuthTokenException(
    super.message, {
    this.isCredentialConfigurationIssue = false,
    super.requiresSignIn,
  });

  factory _CloudOAuthTokenException.fromTokenResponse({
    required _OAuthProviderConfig config,
    required int statusCode,
    required String body,
  }) {
    final lower = body.toLowerCase();
    final mentionsClientSecret =
        lower.contains('client_secret') || lower.contains('client secret');
    if (config.clientIdDefineName == 'GOOGLE_DRIVE_CLIENT_ID' &&
        mentionsClientSecret &&
        lower.contains('missing')) {
      return const _CloudOAuthTokenException(
        'Google Drive reached the token exchange, but Google requested a '
        'client secret. AutoTeleprompter does not embed provider secrets in '
        'public desktop builds; use Local Backup or connect Google Drive after '
        'the secure backend token exchange is available.',
        isCredentialConfigurationIssue: true,
      );
    }
    if (config.clientIdDefineName == 'GOOGLE_DRIVE_CLIENT_ID' &&
        lower.contains('invalid_client')) {
      return const _CloudOAuthTokenException(
        'Google Drive rejected the Desktop OAuth credentials. Verify the '
        'GOOGLE_DRIVE_CLIENT_ID and OAuth consent settings, or use the future '
        'secure backend token exchange for Google account sync.',
        isCredentialConfigurationIssue: true,
      );
    }
    String? code;
    try {
      final payload = jsonDecode(body);
      if (payload is Map) code = payload['error']?.toString();
    } catch (_) {}
    final revoked = code == 'invalid_grant';
    return _CloudOAuthTokenException(
      revoked
          ? 'Access was revoked or expired. Reconnect this account.'
          : 'Cloud renewal unavailable (HTTP $statusCode). Retrying automatically.',
      requiresSignIn: revoked,
      isCredentialConfigurationIssue: code == 'invalid_client',
    );
  }

  @override
  String toString() => message;
}

class _OAuthProviderConfig {
  final String clientId;
  final String? clientSecret;
  final String clientIdDefineName;
  final Uri tokenEndpoint;
  final bool allowDynamicLoopbackPort;
  final Uri Function({
    required String redirectUri,
    required String state,
    required String challenge,
  })
  authorizationUri;
  final Future<String> Function(
    HttpClient client,
    String accessToken,
    Duration timeout,
  )
  accountLabel;

  const _OAuthProviderConfig({
    required this.clientId,
    this.clientSecret,
    required this.clientIdDefineName,
    required this.tokenEndpoint,
    required this.allowDynamicLoopbackPort,
    required this.authorizationUri,
    required this.accountLabel,
  });

  String? get credentialIssue {
    if (clientIdDefineName == 'GOOGLE_DRIVE_CLIENT_ID' &&
        !_looksLikeGoogleOAuthClientId(clientId)) {
      return 'Google Drive account sign-in is ready in code, but '
          'GOOGLE_DRIVE_CLIENT_ID is not a valid OAuth Desktop app Client ID.';
    }
    return null;
  }

  bool shouldRetryWithClientSecret({
    required Map<String, String> parameters,
    required String responseBody,
  }) {
    if (clientIdDefineName != 'GOOGLE_DRIVE_CLIENT_ID') return false;
    if (parameters.containsKey('client_secret')) return false;
    final secret = clientSecret?.trim();
    if (secret == null || secret.isEmpty) return false;
    final lower = responseBody.toLowerCase();
    return lower.contains('client_secret') && lower.contains('missing');
  }

  factory _OAuthProviderConfig.googleDrive({
    required String clientId,
    required String clientSecret,
  }) {
    final normalizedClientId = _cleanOAuthClientId(clientId);
    return _OAuthProviderConfig(
      clientId: normalizedClientId,
      clientSecret: clientSecret.replaceAll(RegExp(r'\s+'), '').trim(),
      clientIdDefineName: 'GOOGLE_DRIVE_CLIENT_ID',
      tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
      allowDynamicLoopbackPort: true,
      authorizationUri:
          ({
            required String redirectUri,
            required String state,
            required String challenge,
          }) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
            'client_id': normalizedClientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope':
                'openid email profile '
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
      tokenEndpoint: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
      allowDynamicLoopbackPort: false,
      authorizationUri:
          ({
            required String redirectUri,
            required String state,
            required String challenge,
          }) => Uri.https('www.dropbox.com', '/oauth2/authorize', {
            'client_id': normalizedClientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'token_access_type': 'offline',
            'scope':
                'account_info.read files.metadata.read '
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
    Duration timeout,
  ) => _accountLabel(client, accessToken, timeout, google: true);

  static Future<String> _dropboxAccountLabel(
    HttpClient client,
    String accessToken,
    Duration timeout,
  ) => _accountLabel(client, accessToken, timeout, google: false);

  static Future<String> _accountLabel(
    HttpClient client,
    String accessToken,
    Duration timeout, {
    required bool google,
  }) async {
    final uri = Uri.parse(
      google
          ? 'https://www.googleapis.com/oauth2/v2/userinfo'
          : 'https://api.dropboxapi.com/2/users/get_current_account',
    );
    final request = await (google ? client.getUrl(uri) : client.postUrl(uri))
        .timeout(timeout);
    request.followRedirects = false;
    try {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      if (!google) {
        request.headers.contentType = ContentType.json;
        request.write('null');
      }
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CloudConnectionException('Account verification failed.');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const CloudConnectionException('Invalid account verification.');
      }
      final email = decoded['email']?.toString().trim() ?? '';
      if (email.isNotEmpty) return email;
      final name = decoded['name'];
      final label =
          (google ? name : (name is Map ? name['display_name'] : null))
              ?.toString()
              .trim() ??
          '';
      if (label.isNotEmpty) return label;
      throw const CloudConnectionException(
        'Missing verified account identity.',
      );
    } finally {
      request.abort(); // Also bounds stalled bodies; never holds callback port.
    }
  }
}
