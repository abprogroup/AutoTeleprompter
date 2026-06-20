part of 'app_settings_screen.dart';

const _accountManageSubscriptionUrl = String.fromEnvironment(
  'ACCOUNT_MANAGE_SUBSCRIPTION_URL',
);

extension _AccountSubscriptionSettings on _AppSettingsScreenState {
  List<Widget> _accountSubscriptionSection(AuthState auth) {
    final manageUrl = _accountManageSubscriptionUrl.trim();
    return [
      const SizedBox(height: 22),
      const _SectionHeader(title: 'SUBSCRIPTION'),
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.workspace_premium_outlined,
        title: 'Plan status',
        subtitle: _subscriptionStatusSubtitle(auth),
      ),
      if (manageUrl.isNotEmpty) ...[
        const SizedBox(height: 8),
        _SettingsTile(
          icon: Icons.open_in_browser_rounded,
          title: 'Manage subscription',
          subtitle: 'Opens your account page in the external browser',
          onTap: () => _openExternalAccountUrl(manageUrl),
        ),
      ],
      const SizedBox(height: 8),
      _SettingsTile(
        icon: Icons.refresh_rounded,
        title: 'Restore / refresh entitlement',
        subtitle: 'Re-check after payment, renewal, or admin changes',
        onTap: _refreshAccountEntitlement,
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

  Future<void> _refreshAccountEntitlement() async {
    try {
      final active =
          await ref.read(authProvider.notifier).refreshBackendAccount();
      if (!mounted) return;
      _showAccountSnack(
        active
            ? 'Account status refreshed.'
            : 'Account refreshed. Premium is not active.',
      );
    } catch (error) {
      if (!mounted) return;
      _showAccountSnack(_accountBackendMessage(error));
    }
  }

  Future<void> _openExternalAccountUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showAccountSnack('Subscription portal is not configured.');
      return;
    }
    try {
      final opened = await ExternalUrlLauncher.openUrl(uri.toString());
      if (opened) return;
      throw StateError('External launcher reported failure for $uri');
    } catch (error) {
      final message = sanitizeSettingsErrorForUser(error);
      _showAccountSnack('Could not open subscription portal: $message');
    }
  }
}
