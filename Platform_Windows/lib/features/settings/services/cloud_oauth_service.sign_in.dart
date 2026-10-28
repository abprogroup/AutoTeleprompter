part of 'cloud_oauth_service.dart';

class _SignInCancelled implements Exception {}

class _CloudSignInAttempt {
  final _cancelled = Completer<void>();
  bool committing = false;
  void cancel() {
    if (!committing && !_cancelled.isCompleted) _cancelled.complete();
  }

  void check() {
    if (_cancelled.isCompleted) throw _SignInCancelled();
  }

  Future<T> guard<T>(Future<T> work) => Future.any([
    work,
    _cancelled.future.then<T>((_) => throw _SignInCancelled()),
  ]);
}

extension _CloudOAuthSignIn on CloudOAuthService {
  Future<CloudAccountConnectResult> _connectAccount(
    CloudProviderDefinition provider,
  ) async {
    CloudAccountConnectResult failure(String message) =>
        CloudAccountConnectResult(connected: false, message: message);
    if (_signInAttempt != null) {
      return failure(
        'A cloud sign-in is already open. Finish it or use Cancel sign-in first.',
      );
    }
    final config = _oauthConfigFor(provider);
    if (config == null) {
      return CloudAccountConnectResult(
        connected: false,
        unsupported: true,
        message:
            '${provider.label} direct sign-in is unavailable. Use its local synced folder.',
      );
    }
    if (config.clientId.isEmpty || config.credentialIssue != null) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: true,
        message:
            config.credentialIssue ??
            '${provider.label} sign-in configuration is missing.',
      );
    }
    // Guard synchronously, across providers and all shared service callers.
    final attempt = _CloudSignInAttempt();
    _signInAttempt = attempt;
    activeSignIn.value = provider.id;
    final originalEpoch = _epochs[provider.id] ?? 0;
    CloudSignInLease? lease;
    CloudOAuthCallbackSession? callbackSession;
    try {
      lease = await _signInRuntime.acquireLease();
      attempt.check();
      if (lease == null) {
        return failure(
          'Another AutoTeleprompter window has a cloud sign-in open. '
          'Finish or cancel it there, then try again. Your saved connection is unchanged.',
        );
      }
      final server = await _bindOAuthCallbackServer(config);
      final state = _randomBase64Url(24);
      callbackSession = CloudOAuthCallbackSession(server, state);
      attempt.check();
      final redirectUri = 'http://localhost:${server.port}/oauth/callback';
      final verifier = _randomBase64Url(64);
      await attempt.guard(
        _signInRuntime
            .openBrowser(
              config.authorizationUri(
                redirectUri: redirectUri,
                state: state,
                challenge: _pkceChallenge(verifier),
              ),
            )
            .timeout(_requestTimeout),
      );
      final callback = await attempt.guard(
        callbackSession.result.timeout(_signInRuntime.callbackTimeout),
      );
      // Release the registered port BEFORE token exchange or account lookup.
      await callbackSession.close();
      attempt.check();
      if (callback.error != null) {
        return failure(
          '${provider.label} sign-in was cancelled or rejected. '
          'Your saved connection is unchanged.',
        );
      }
      final code = callback.code;
      if (code == null || code.isEmpty) {
        return failure(
          '${provider.label} did not return an authorization code.',
        );
      }
      final tokens = await attempt.guard(
        _exchangeCode(
          config: config,
          code: code,
          verifier: verifier,
          redirectUri: redirectUri,
        ),
      );
      final access = tokens['access_token']?.toString().trim() ?? '';
      if (access.isEmpty ||
          (tokens['refresh_token']?.toString().isEmpty ?? true) ||
          tokens['expires_in'] is! num ||
          (tokens['expires_in'] as num) <= 0) {
        return failure(
          '${provider.label} did not return renewable credentials. '
          'Your saved connection is unchanged.',
        );
      }
      final label = await attempt.guard(
        config.accountLabel(_httpClient, access, _requestTimeout),
      );
      final account = CloudAccountInfo(
        providerId: provider.id,
        providerLabel: provider.label,
        accountLabel: label,
        connectedAtIso: _now().toUtc().toIso8601String(),
        expiresAtIso: _expiresAtIso(tokens),
      );
      // Let an existing renewal finish before replacing its credential. A failed
      // reconnect must not invalidate an unrelated in-flight working refresh.
      final renewal = _pending[provider.id];
      if (renewal != null) {
        await attempt.guard(renewal.then<void>((_) {}, onError: (Object _) {}));
      }
      attempt.check();
      if ((_epochs[provider.id] ?? 0) != originalEpoch) {
        return failure(
          'Connection changed while signing in. Please try again.',
        );
      }
      // No cancellation once the validated encrypted replacement begins. A
      // disconnect still wins through the epoch check and serialized deletion.
      attempt.committing = true;
      final epoch = originalEpoch + 1;
      _epochs[provider.id] = epoch;
      await _saveEncryptedAccount(provider.id, account, tokens, epoch: epoch);
      if ((_epochs[provider.id] ?? 0) != epoch) {
        return failure('Connection changed while signing in.');
      }
      _retry.remove(provider.id);
      _setConnectionStatus(provider.id, CloudConnectionStatus.available);
      return CloudAccountConnectResult(
        connected: true,
        account: account,
        message: '${provider.label} connected as $label.',
      );
    } on _SignInCancelled {
      return failure('Sign-in cancelled. Your saved connection is unchanged.');
    } on TimeoutException {
      return failure(
        '${provider.label} sign-in timed out. Try again when ready. '
        'Your saved connection is unchanged.',
      );
    } on SocketException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 10048 || code == 98 || code == 48) {
        return failure(
          'The cloud sign-in callback port is in use by another '
          'sign-in or program. No program was stopped. Your saved connection is unchanged.',
        );
      }
      return failure(
        'Cloud sign-in could not open its local callback or network connection. '
        'Check network/firewall permissions and try again. Your saved connection is unchanged.',
      );
    } on _CloudOAuthTokenException catch (error) {
      return CloudAccountConnectResult(
        connected: false,
        missingCredentials: error.isCredentialConfigurationIssue,
        message: '${error.message} Your saved connection is unchanged.',
      );
    } catch (_) {
      // Never echo provider bodies, codes, tokens or local paths into the UI.
      return failure(
        '${provider.label} sign-in could not be completed. '
        'Your saved connection is unchanged. Please try again.',
      );
    } finally {
      try {
        await callbackSession?.close();
      } finally {
        try {
          await lease?.release();
        } finally {
          if (identical(_signInAttempt, attempt)) {
            _signInAttempt = null;
            activeSignIn.value = null;
          }
        }
      }
    }
  }

  Future<CloudAccountConnectResult> _checkAccountConnection(
    CloudProviderDefinition provider,
  ) async {
    final epoch = _epochs[provider.id] ?? 0;
    bool current() => (_epochs[provider.id] ?? 0) == epoch;
    const changed = CloudAccountConnectResult(
      connected: false,
      message:
          'Connection changed while checking. Check the current account again if needed.',
    );
    try {
      final session = await authorizeAccount(provider.id);
      if (!current()) return changed;
      final config = _oauthConfigFor(provider);
      if (session == null || config == null) {
        return const CloudAccountConnectResult(
          connected: false,
          message: 'No saved connection. Connect this account first.',
        );
      }
      await config.accountLabel(
        _httpClient,
        session.accessToken,
        _requestTimeout,
      );
      if (!current()) return changed;
      return CloudAccountConnectResult(
        connected: true,
        account: session.account,
        message: '${provider.label} connection verified.',
      );
    } catch (_) {
      // A response for an old connection says nothing about the new state,
      // whether it succeeded or failed. Disconnect/reconnect stays authoritative.
      if (!current()) return changed;
      return CloudAccountConnectResult(
        connected: false,
        message:
            '${provider.label} could not be verified right now. '
            'Check your internet connection; reconnect if access was revoked. '
            'Your saved account has not been removed.',
      );
    }
  }
}
