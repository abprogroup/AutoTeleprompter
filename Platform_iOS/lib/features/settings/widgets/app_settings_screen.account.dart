part of 'app_settings_screen.dart';

extension _SettingsAccountActions on _AppSettingsScreenState {
  String _accountSubtitle(AuthState auth) {
    if (auth.isCheckingBackendAccess) return 'Checking account access...';
    if (auth.hasPremiumAccess) {
      final email = auth.email?.trim();
      return email == null || email.isEmpty
          ? 'Premium tools unlocked'
          : 'Signed in as $email';
    }
    if (auth.accountBackendEnabled && auth.backendStatus == 'notConfigured') {
      return 'Account backend is not configured for this build';
    }
    return 'Sign in to unlock Pro tools';
  }

  void _openLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(initialPasswordMode: true),
      ),
    );
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final current = ref.read(settingsProvider).displayName;
    final name = await _textInputDialog(
      title: 'Display Name',
      label: 'Your name',
      initialValue: current,
      actionLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(settingsProvider.notifier).setDisplayName(name.trim());
    _showSnack('Display name updated.');
  }

  Future<void> _setOrChangePassword() async {
    final current = await _textInputDialog(
      title: 'Current password',
      label: 'Leave empty if this account has no password yet',
      obscureText: true,
      actionLabel: 'Next',
      allowEmpty: true,
    );
    if (current == null) return;
    final next = await _textInputDialog(
      title: 'New password',
      label: 'At least 8 characters',
      obscureText: true,
      actionLabel: 'Save',
    );
    if (next == null) return;
    try {
      await ref.read(authProvider.notifier).setBackendPassword(
            currentPassword: current.trim().isEmpty ? null : current,
            newPassword: next,
          );
      _showSnack('Password updated.');
    } catch (error) {
      _showSnack('Password update failed: $error');
    }
  }

  Future<void> _resetPasswordWithCode() async {
    final auth = ref.read(authProvider);
    final email = await _textInputDialog(
      title: 'Reset password',
      label: 'Account email',
      initialValue: auth.email ?? auth.lastEmailUsed ?? '',
      keyboardType: TextInputType.emailAddress,
      actionLabel: 'Send code',
    );
    if (email == null || email.trim().isEmpty) return;
    try {
      await ref
          .read(authProvider.notifier)
          .requestBackendPasswordResetCode(email.trim());
      _showSnack('Password reset code sent.');
    } catch (error) {
      _showSnack('Could not send reset code: $error');
      return;
    }
    final code = await _textInputDialog(
      title: 'Verification code',
      label: 'Code from email',
      actionLabel: 'Next',
    );
    if (code == null || code.trim().isEmpty) return;
    final password = await _textInputDialog(
      title: 'New password',
      label: 'At least 8 characters',
      obscureText: true,
      actionLabel: 'Save',
    );
    if (password == null) return;
    try {
      await ref.read(authProvider.notifier).resetBackendPasswordWithCode(
            email: email.trim(),
            code: code.trim(),
            newPassword: password,
          );
      _showSnack('Password reset complete.');
    } catch (error) {
      _showSnack('Password reset failed: $error');
    }
  }

  Future<void> _changeEmailWithCode() async {
    final newEmail = await _textInputDialog(
      title: 'Change email',
      label: 'New email address',
      keyboardType: TextInputType.emailAddress,
      actionLabel: 'Send code',
    );
    if (newEmail == null || newEmail.trim().isEmpty) return;
    final password = await _textInputDialog(
      title: 'Confirm password',
      label: 'Current account password',
      obscureText: true,
      actionLabel: 'Send code',
    );
    if (password == null) return;
    try {
      await ref.read(authProvider.notifier).changeBackendEmailWithPassword(
            newEmail: newEmail.trim(),
            currentPassword: password,
          );
      _showSnack('Email change code sent.');
    } catch (error) {
      _showSnack('Could not start email change: $error');
      return;
    }
    final code = await _textInputDialog(
      title: 'Confirm email',
      label: 'Code sent to the new email',
      actionLabel: 'Confirm',
    );
    if (code == null || code.trim().isEmpty) return;
    try {
      await ref.read(authProvider.notifier).verifyBackendEmailChangeCode(
            newEmail: newEmail.trim(),
            code: code.trim(),
          );
      _showSnack('Email updated.');
    } catch (error) {
      _showSnack('Email confirmation failed: $error');
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await _confirmDialog(
      title: 'Sign out?',
      body: 'Your scripts and local settings stay on this iPhone.',
      actionLabel: 'Sign out',
    );
    if (confirmed != true) return;
    await ref.read(authProvider.notifier).logout();
    _showSnack('Signed out.');
  }

  Future<void> _deleteAccount() async {
    final confirmation = await _textInputDialog(
      title: 'Delete account',
      label: 'Type DELETE to confirm',
      actionLabel: 'Delete',
    );
    if (confirmation != 'DELETE') return;
    try {
      await ref
          .read(authProvider.notifier)
          .deleteBackendAccount(confirmation: confirmation!);
      _showSnack('Account deleted.');
    } catch (error) {
      _showSnack('Account deletion failed: $error');
    }
  }

  Future<String?> _textInputDialog({
    required String title,
    required String label,
    String initialValue = '',
    String actionLabel = 'OK',
    bool obscureText = false,
    bool allowEmpty = false,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFFBF00)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text;
              if (!allowEmpty && text.trim().isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String body,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(body, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  void _showConsentDetails() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Privacy and consent',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'AutoTeleprompter can store scripts locally, sync through connected '
            'cloud options, use microphone/camera permissions for presentation '
            'and recording, and send feedback diagnostics only when you submit '
            'a report. Script attachment is optional on every feedback report.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // Subscription / entitlement section (macOS parity). On iOS the "Manage
  // subscription" link opens the account portal in the browser; Apple in-app
  // purchase management would route to the App Store instead if IAP is used.
  List<Widget> _accountSubscriptionSection(AuthState auth) {
    final manageUrl = _accountManageSubscriptionUrl.trim();
    return [
      const _SectionHeader(title: 'SUBSCRIPTION'),
      _SettingsTile(
        icon: Icons.workspace_premium_outlined,
        iconColor: const Color(0xFFFFBF00),
        title: 'Plan status',
        subtitle: _subscriptionStatusSubtitle(auth),
      ),
      if (manageUrl.isNotEmpty)
        _SettingsTile(
          icon: Icons.open_in_browser_rounded,
          title: 'Manage subscription',
          subtitle: 'Opens your account page in the external browser.',
          onTap: () => unawaited(_openExternalAccountUrl(manageUrl)),
        ),
      _SettingsTile(
        icon: Icons.refresh_rounded,
        title: 'Restore / refresh entitlement',
        subtitle: 'Re-check after payment, renewal, or admin changes.',
        onTap: () => unawaited(_refreshAccountEntitlement()),
      ),
    ];
  }

  String _subscriptionStatusSubtitle(AuthState auth) {
    if (auth.isCheckingBackendAccess) return 'Checking account status...';
    final status = auth.entitlementStatus;
    if (auth.backendRole == AccountBackendRole.admin && status == 'active') {
      return 'Admin - non-expiring owner access';
    }
    if (auth.backendRole == AccountBackendRole.pro) {
      final expiry = auth.entitlementExpiresAt;
      if (status == 'expired') return 'Pro expired';
      if (status == 'revoked') return 'Pro revoked';
      if (expiry != null) return 'Pro - renews ${_formatAccountDate(expiry)}';
      return 'Pro active';
    }
    if (status == 'disabled') return 'Account disabled';
    if (status == 'revoked') return '${auth.roleLabel} revoked';
    if (status == 'expired') return '${auth.roleLabel} expired';
    return 'Free - no active subscription';
  }

  String _formatAccountDate(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _refreshAccountEntitlement() async {
    try {
      final active =
          await ref.read(authProvider.notifier).refreshBackendAccount();
      _showSnack(
        active
            ? 'Account status refreshed.'
            : 'Account refreshed. Premium is not active.',
      );
    } catch (error) {
      _showSnack('Account refresh failed: ${sanitizeSettingsErrorForUser(error)}');
    }
  }

  Future<void> _openExternalAccountUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showSnack('Subscription portal is not configured.');
      return;
    }
    try {
      final opened = await ExternalUrlLauncher.openUrl(uri.toString());
      if (!opened) throw StateError('External launcher failed for $uri');
    } catch (error) {
      _showSnack(
        'Could not open subscription portal: '
        '${sanitizeSettingsErrorForUser(error)}',
      );
    }
  }
}

const _accountManageSubscriptionUrl = String.fromEnvironment(
  'ACCOUNT_MANAGE_SUBSCRIPTION_URL',
);
