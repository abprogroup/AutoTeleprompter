part of 'app_settings_screen.dart';

extension _AccountSettingsTab on _AppSettingsScreenState {
  List<Widget> _accountTab(AppSettings settings, AuthState auth) {
    final signedIn = auth.email != null && auth.email!.trim().isNotEmpty;
    final accountStatus =
        signedIn ? _accountConnectionSubtitle(auth) : 'Not connected';

    return [
      const _SectionHeader(title: 'PROFILE'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.person_outline,
        title: 'Display Name',
        subtitle: settings.displayName,
        onTap: () => _editDisplayName(context),
      ),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: signedIn
            ? Icons.verified_user_outlined
            : Icons.person_add_alt_1_outlined,
        title: signedIn ? 'Account connection' : 'Connect account',
        subtitle: signedIn
            ? accountStatus
            : 'Connect a Pro account when account services are ready',
        onTap: signedIn ? null : _openAccountActivation,
      ),
      if (signedIn) ...[
        ..._accountSubscriptionSection(auth),
        const SizedBox(height: 22),
        const _SectionHeader(title: 'SECURITY'),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.password_outlined,
          title: 'Set / change password',
          subtitle: 'Password is handled by Supabase Auth',
          onTap: () => _showSetPasswordDialog(auth),
        ),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.lock_reset_rounded,
          title: 'Reset password by email',
          subtitle: 'Sends a reset code to your account email',
          onTap: () => _showResetPasswordDialog(auth),
        ),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.alternate_email_rounded,
          title: 'Change account email',
          subtitle: 'Requires your password before sending confirmation',
          onTap: () => _showChangeEmailDialog(auth),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 22),
        const _SectionHeader(title: 'ACCOUNT'),
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign out on this device',
          subtitle: 'Keeps local scripts, clears the account shell',
          onTap: _signOutAccount,
        ),
        ..._accountDangerSection(auth),
      ],
      const SizedBox(height: 22),
      const _SectionHeader(title: 'PRIVACY'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.privacy_tip_outlined,
        title: 'Privacy Consent',
        subtitle: 'Review device key, policy version, and consent status',
        onTap: () => _showBetaConsentDetails(context),
      ),
    ];
  }

  void _openAccountActivation() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _signOutAccount() async {
    await ref.read(authProvider.notifier).logout();
    await ref.read(settingsProvider.notifier).resetDisplayNameToGuest();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signed out on this device.')),
    );
  }

  String _accountConnectionSubtitle(AuthState auth) {
    final email = auth.email?.trim();
    final label = _accountRoleStatusLabel(auth);
    return email == null || email.isEmpty ? label : '$email - $label';
  }

  String _accountRoleStatusLabel(AuthState auth) {
    if (auth.isCheckingBackendAccess) return 'checking account';
    if (auth.backendStatus == 'disabledAccount') return 'account disabled';
    if (auth.entitlementStatus == 'revoked') return '${auth.roleLabel} revoked';
    if (auth.entitlementStatus == 'expired') return '${auth.roleLabel} expired';
    if (auth.backendRole == AccountBackendRole.admin) return 'Admin';
    if (auth.backendRole == AccountBackendRole.pro) {
      final expiry = auth.entitlementExpiresAt;
      if (expiry != null) return 'Pro - renews ${_formatAccountDate(expiry)}';
      return 'Pro';
    }
    return 'Free';
  }

  String _formatAccountDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  void _showSetPasswordDialog(AuthState auth) {
    final currentController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var busy = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Set / change password',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AccountDialogTextField(
                controller: currentController,
                label: 'Current password (if already set)',
                obscure: true,
              ),
              const SizedBox(height: 12),
              _AccountDialogTextField(
                controller: passwordController,
                label: 'New password',
                obscure: true,
              ),
              const SizedBox(height: 12),
              _AccountDialogTextField(
                controller: confirmController,
                label: 'Confirm new password',
                obscure: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final dialogNavigator = Navigator.of(ctx);
                      if (passwordController.text != confirmController.text) {
                        _showAccountSnack('Passwords do not match.');
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await ref
                            .read(authProvider.notifier)
                            .setBackendPassword(
                              newPassword: passwordController.text,
                              currentPassword: currentController.text,
                            );
                        if (!mounted) return;
                        dialogNavigator.pop();
                        _showAccountSnack('Password updated.');
                      } catch (error) {
                        setDialogState(() => busy = false);
                        _showAccountSnack(_accountBackendMessage(error));
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(AuthState auth) {
    final emailController = TextEditingController(text: auth.email ?? '');
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    var codeRequested = false;
    var busy = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Reset password',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AccountDialogTextField(
                controller: emailController,
                label: 'Account email',
              ),
              if (codeRequested) ...[
                const SizedBox(height: 12),
                _AccountDialogTextField(
                  controller: codeController,
                  label: 'Reset code',
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _AccountDialogTextField(
                  controller: passwordController,
                  label: 'New password',
                  obscure: true,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final dialogNavigator = Navigator.of(ctx);
                      setDialogState(() => busy = true);
                      try {
                        final notifier = ref.read(authProvider.notifier);
                        if (!codeRequested) {
                          await notifier.requestBackendPasswordResetCode(
                            emailController.text,
                          );
                          setDialogState(() {
                            codeRequested = true;
                            busy = false;
                          });
                          _showAccountSnack('Password reset code sent.');
                          return;
                        }
                        await notifier.resetBackendPasswordWithCode(
                          email: emailController.text,
                          code: codeController.text,
                          newPassword: passwordController.text,
                        );
                        if (!mounted) return;
                        dialogNavigator.pop();
                        _showAccountSnack('Password reset complete.');
                      } catch (error) {
                        setDialogState(() => busy = false);
                        _showAccountSnack(_accountBackendMessage(error));
                      }
                    },
              child: Text(codeRequested ? 'Reset' : 'Send code'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeEmailDialog(AuthState auth) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final codeController = TextEditingController();
    var busy = false;
    var codeRequested = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Change account email',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AccountDialogTextField(
                controller: emailController,
                label: 'New email',
              ),
              const SizedBox(height: 12),
              if (!codeRequested)
                _AccountDialogTextField(
                  controller: passwordController,
                  label: 'Current password',
                  obscure: true,
                )
              else
                _AccountDialogTextField(
                  controller: codeController,
                  label: 'Email confirmation code',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final dialogNavigator = Navigator.of(ctx);
                      setDialogState(() => busy = true);
                      try {
                        final notifier = ref.read(authProvider.notifier);
                        if (!codeRequested) {
                          await notifier.changeBackendEmailWithPassword(
                            newEmail: emailController.text,
                            currentPassword: passwordController.text,
                          );
                          if (!mounted) return;
                          setDialogState(() {
                            codeRequested = true;
                            busy = false;
                          });
                          _showAccountSnack(
                            'Email change code sent to the new inbox.',
                          );
                          return;
                        }
                        await notifier.verifyBackendEmailChangeCode(
                          newEmail: emailController.text,
                          code: codeController.text,
                        );
                        if (!mounted) return;
                        dialogNavigator.pop();
                        _showAccountSnack('Account email updated.');
                      } catch (error) {
                        setDialogState(() => busy = false);
                        _showAccountSnack(_accountBackendMessage(error));
                      }
                    },
              child: Text(codeRequested ? 'Confirm email' : 'Send code'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _accountBackendMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('weak_password')) {
      return 'Password must be at least 8 characters.';
    }
    if (text.contains('invalid') || text.contains('expired')) {
      return 'The code or password is invalid. Please try again.';
    }
    if (text.contains('signed_out')) {
      return 'Please sign in again first.';
    }
    return 'Account security update failed: ${_compactBackendError(error)}';
  }

  String _compactBackendError(Object error) {
    final message = error.toString();
    const prefix = 'AccountBackendError(';
    final compact = !message.startsWith(prefix) || !message.endsWith(')')
        ? message
        : message
            .substring(prefix.length, message.length - 1)
            .replaceFirst(', ', ': ');
    return sanitizeSettingsErrorForUser(compact);
  }
}

class _AccountDialogTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;

  const _AccountDialogTextField({
    required this.controller,
    required this.label,
    this.obscure = false,
  });

  @override
  State<_AccountDialogTextField> createState() =>
      _AccountDialogTextFieldState();
}

class _AccountDialogTextFieldState extends State<_AccountDialogTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscure && !_visible,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white54),
        suffixIcon: widget.obscure
            ? IconButton(
                icon: Icon(
                  _visible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white54,
                ),
                onPressed: () => setState(() => _visible = !_visible),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
