part of 'app_settings_screen.dart';

extension _AccountSettingsTab on _AppSettingsScreenState {
  List<Widget> _accountTab(AppSettings settings, AuthState auth) {
    final signedIn = auth.email != null && auth.email!.trim().isNotEmpty;
    final accountStatus = signedIn
        ? '${auth.email}${auth.isPro ? ' - Pro' : ' - Free'}'
        : 'Not connected';

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
      const _SectionHeader(title: 'ACCOUNT SECURITY'),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.lock_reset_rounded,
        title: 'Password reset',
        subtitle: 'Future server-backed account feature',
      ),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.alternate_email_rounded,
        title: 'Account migration email',
        subtitle: signedIn
            ? 'Current account email: ${auth.email}'
            : 'Future migration will require a verified account email',
      ),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.pin_outlined,
        title: 'Account PIN security',
        subtitle: 'Future quick unlock and sensitive-action protection',
      ),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.devices_other_outlined,
        title: 'Trusted devices',
        subtitle: 'Future device review, revocation, and login alerts',
      ),
      const SizedBox(height: 22),
      const _SectionHeader(title: 'ACCOUNT DATA'),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.download_for_offline_outlined,
        title: 'Export account data',
        subtitle: 'Future export for server-backed accounts and cloud records',
      ),
      const SizedBox(height: 8),
      const _SettingsTile(
        icon: Icons.delete_forever_outlined,
        title: 'Delete account data',
        subtitle: 'Future account/cloud deletion with confirmation',
      ),
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signed out on this device.')),
    );
  }
}
