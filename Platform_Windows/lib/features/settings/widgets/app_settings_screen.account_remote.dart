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
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.logout_rounded,
          title: 'Sign out on this device',
          subtitle: 'Keeps local scripts, clears the account shell',
          onTap: _signOutAccount,
        ),
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
}
