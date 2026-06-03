part of 'script_editor_screen.dart';

extension _ScriptEditorPremiumGate on _ScriptEditorScreenState {
  bool get _hasEditorPremiumAccess {
    final auth = ref.read(authProvider);
    return auth.isPro || auth.isAdmin;
  }

  bool _watchEditorPremiumAccess() {
    final auth = ref.watch(authProvider);
    return auth.isPro || auth.isAdmin;
  }

  Future<bool> _ensureEditorPremiumAccess(String featureName) async {
    if (_hasEditorPremiumAccess) return true;
    if (!mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('$featureName requires Pro access.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Connect',
          onPressed: () {
            messenger.hideCurrentSnackBar();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
        ),
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4)).then((_) {
        controller.close();
      }),
    );
    return false;
  }
}
