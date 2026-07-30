part of 'script_editor_screen.dart';

/// Gates Bookmarks, Content Creator, and Audio-only recording behind Pro
/// access - per Amit's explicit direction, this is the intended behavior
/// for free users, not a silent removal of a feature.
///
/// 2026-07-30: switched from a snackbar-with-action (Windows' pattern) to a
/// confirm dialog (iOS's pattern) - checked iOS, the actual same-form-factor
/// mobile precedent, rather than continuing to derive mobile UX from
/// Windows. The dialog also re-checks premium status after a successful
/// sign-in and returns `true` immediately, instead of Windows' pattern which
/// always returns `false` and makes the user tap the locked control a
/// second time after connecting.
extension _ScriptEditorPremiumGate on _ScriptEditorScreenState {
  bool get _hasEditorPremiumAccess {
    final auth = ref.read(authProvider);
    return auth.hasPremiumAccess;
  }

  bool _watchEditorPremiumAccess() {
    final auth = ref.watch(authProvider);
    return auth.hasPremiumAccess;
  }

  Future<bool> _ensureEditorPremiumAccess(String featureName) async {
    if (_hasEditorPremiumAccess) return true;
    if (!mounted) return false;
    final shouldSignIn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          '$featureName requires Pro',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Sign in with a Pro account to unlock this feature.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (shouldSignIn == true) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(initialPasswordMode: true),
        ),
      );
      if (!mounted) return false;
    }
    return _hasEditorPremiumAccess;
  }
}
