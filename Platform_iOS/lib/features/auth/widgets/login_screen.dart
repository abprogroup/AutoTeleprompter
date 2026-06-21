import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _isLoading = false;
  bool _backendCodeRequested = false;
  bool _passwordMode = false;
  bool _prefillingEmail = false;
  bool _emailEditedByUser = false;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_trackEmailEdits);
    _licenseCtrl.addListener(_refreshBackendCodeState);
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_trackEmailEdits);
    _licenseCtrl.removeListener(_refreshBackendCodeState);
    _emailCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  void _trackEmailEdits() {
    if (_prefillingEmail) return;
    _emailEditedByUser = true;
  }

  void _refreshBackendCodeState() {
    if (mounted && ref.read(authProvider).accountBackendEnabled) {
      setState(() {});
    }
  }

  Future<void> _handleActivation() async {
    final auth = ref.read(authProvider);
    if (auth.accountBackendEnabled) {
      await _handleBackendActivation();
      return;
    }

    final email = _emailCtrl.text.trim();
    final license = _licenseCtrl.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your workspace email.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.login(email);
    await ref.read(settingsProvider.notifier).seedDisplayNameFromEmail(email);

    bool success = false;
    if (license.isNotEmpty) {
      success = await authNotifier.activateLicense(license);
    } else {
      success = ref.read(authProvider).hasPremiumAccess;
    }

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Professional suite activated.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        final message = isLocalProLicenseActivationConfigured
            ? 'Invalid license. Please check and try again.'
            : 'License verification is not configured in this installation.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _handleBackendActivation() async {
    final email = _emailCtrl.text.trim();
    final credential = _licenseCtrl.text.trim();

    if (email.isEmpty) {
      _showSnack('Please enter your workspace email.');
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    setState(() => _isLoading = true);
    try {
      if (_passwordMode) {
        if (credential.isEmpty) {
          _showSnack('Please enter your password.');
          setState(() => _isLoading = false);
          return;
        }
        final success = await authNotifier.signInWithBackendPassword(
          email: email,
          password: credential,
        );
        await ref
            .read(settingsProvider.notifier)
            .seedDisplayNameFromEmail(email);
        setState(() => _isLoading = false);
        if (!success) {
          _showSnack('This account does not have active Pro access.');
          return;
        }
        _finishSuccessfulBackendLogin();
        return;
      }

      if (credential.isEmpty) {
        await authNotifier.requestBackendLoginCode(email);
        setState(() {
          _backendCodeRequested = true;
          _isLoading = false;
        });
        _showSnack('Verification code sent. Check your email.');
        return;
      }

      final success = await authNotifier.verifyBackendLoginCode(
        email: email,
        code: credential,
      );
      await ref.read(settingsProvider.notifier).seedDisplayNameFromEmail(email);
      setState(() => _isLoading = false);
      if (!success) {
        _showSnack('This account does not have active Pro access.');
        return;
      }
      _finishSuccessfulBackendLogin();
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack(_friendlyBackendError(error));
    }
  }

  void _finishSuccessfulBackendLogin() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Professional suite activated.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _friendlyBackendError(Object error) {
    final message = error.toString();
    if (message.contains('over_email_send_rate_limit')) {
      return 'Please wait a moment before requesting another code.';
    }
    if (message.contains('weak_password')) {
      return 'Password must be at least 8 characters.';
    }
    if (message.contains('invalid_grant') ||
        message.contains('invalid login') ||
        message.contains('invalid_credentials')) {
      return 'Email or password is incorrect.';
    }
    if (message.contains('backend_not_configured')) {
      return 'Account backend is not configured for this build.';
    }
    if (message.contains('invalid') || message.contains('expired')) {
      return _passwordMode
          ? 'Email or password is incorrect.'
          : 'Invalid or expired verification code.';
    }
    if (message.startsWith('AccountBackendError(')) {
      return 'Account verification failed: $message';
    }
    return 'Account verification failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final backendMode = auth.accountBackendEnabled;
    _prefillBackendEmail(auth, backendMode);
    final hasBackendCode = backendMode && _licenseCtrl.text.trim().isNotEmpty;
    final codeRequested =
        backendMode && (_backendCodeRequested || hasBackendCode);
    final credentialLabel = backendMode
        ? _passwordMode
            ? 'Password'
            : 'Email Verification Code'
        : 'Professional License Key';
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFBF00),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 64,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'AutoTeleprompter',
                style: GoogleFonts.bebasNeue(
                  letterSpacing: 2,
                  fontSize: 32,
                  color: const Color(0xFFFFBF00),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'The ultimate tool for high-end broadcasting',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 48),
              _LoginTextField(
                controller: _emailCtrl,
                label: 'Workspace Email',
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 16),
              _LoginTextField(
                controller: _licenseCtrl,
                label: credentialLabel,
                icon: Icons.vpn_key_outlined,
                // OTP/verification codes are not secret — show them in clear
                // text (no mask, no eye toggle). Only mask real passwords and
                // the offline license key.
                isObscure: _passwordMode || !backendMode,
                showVisibilityToggle: backendMode && _passwordMode,
              ),
              if (backendMode) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _passwordMode = !_passwordMode;
                                _licenseCtrl.clear();
                                _backendCodeRequested = false;
                              });
                            },
                      child: Text(
                        _passwordMode
                            ? 'Use email verification code'
                            : 'Use password instead',
                      ),
                    ),
                    if (_passwordMode)
                      TextButton(
                        onPressed: _isLoading ? null : _showPasswordResetDialog,
                        child: const Text('Forgot password?'),
                      ),
                  ],
                ),
                CheckboxListTile(
                  value: auth.rememberMe,
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          ref
                              .read(authProvider.notifier)
                              .setBackendRememberMe(value ?? true);
                        },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: const Color(0xFFFFBF00),
                  checkColor: Colors.black,
                  title: const Text(
                    'Remember me',
                    style: TextStyle(color: Colors.white70),
                  ),
                  subtitle: const Text(
                    'Keep this account connected after closing the app.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleActivation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBF00),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          backendMode
                              ? _passwordMode
                                  ? 'SIGN IN WITH PASSWORD'
                                  : codeRequested
                                      ? 'VERIFY ACCOUNT'
                                      : 'SEND VERIFICATION CODE'
                              : 'ACTIVATE LICENSE',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _showPurchaseDialog(context),
                child: const Text(
                  'NEED A LICENSE?',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _prefillBackendEmail(AuthState auth, bool backendMode) {
    if (!backendMode || _emailEditedByUser || _emailCtrl.text.isNotEmpty) {
      return;
    }
    final email = (auth.email ?? auth.lastEmailUsed ?? '').trim();
    if (email.isEmpty) return;
    _prefillingEmail = true;
    _emailCtrl.text = email;
    _prefillingEmail = false;
  }

  void _showPasswordResetDialog() {
    final emailController = TextEditingController(text: _emailCtrl.text.trim());
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
              _DialogTextField(
                controller: emailController,
                label: 'Account email',
              ),
              if (codeRequested) ...[
                const SizedBox(height: 12),
                _DialogTextField(
                  controller: codeController,
                  label: 'Reset code',
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _DialogTextField(
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
                      final screenNavigator = Navigator.of(context);
                      setDialogState(() => busy = true);
                      try {
                        final auth = ref.read(authProvider.notifier);
                        if (!codeRequested) {
                          await auth.requestBackendPasswordResetCode(
                            emailController.text,
                          );
                          setDialogState(() {
                            codeRequested = true;
                            busy = false;
                          });
                          _showSnack('Password reset code sent.');
                          return;
                        }
                        await auth.resetBackendPasswordWithCode(
                          email: emailController.text,
                          code: codeController.text,
                          newPassword: passwordController.text,
                        );
                        if (!mounted) return;
                        dialogNavigator.pop();
                        screenNavigator.pop();
                        _showSnack('Password reset complete.');
                      } catch (error) {
                        setDialogState(() => busy = false);
                        _showSnack(_friendlyBackendError(error));
                      }
                    },
              child: Text(codeRequested ? 'Reset' : 'Send code'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPurchaseDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Pro Access',
          style: TextStyle(color: Colors.white),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '- Professional local remote controller',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '- Feedback and diagnostics support',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '- Encrypted local script storage',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '- Future premium tools under active development',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 16),
            Text(
              'Purchases are not connected in this installation. A license '
              'key can activate Pro only when license verification is '
              'configured for the build.',
              style: TextStyle(
                color: Color(0xFFFFBF00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isObscure;
  final bool showVisibilityToggle;

  const _LoginTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.isObscure = false,
    this.showVisibilityToggle = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!showVisibilityToggle) {
      return _LoginTextInput(
        controller: controller,
        label: label,
        icon: icon,
        obscureText: isObscure,
      );
    }
    return _TogglePasswordTextInput(
      controller: controller,
      label: label,
      icon: icon,
    );
  }
}

class _LoginTextInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;

  const _LoginTextInput({
    required this.controller,
    required this.label,
    required this.icon,
    required this.obscureText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: const Color(0xFFFFBF00), size: 18),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TogglePasswordTextInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _TogglePasswordTextInput({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  State<_TogglePasswordTextInput> createState() =>
      _TogglePasswordTextInputState();
}

class _TogglePasswordTextInputState extends State<_TogglePasswordTextInput> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(widget.icon, color: const Color(0xFFFFBF00), size: 18),
        suffixIcon: IconButton(
          icon: Icon(
            _visible ? Icons.visibility_off : Icons.visibility,
            color: Colors.white54,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DialogTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;

  const _DialogTextField({
    required this.controller,
    required this.label,
    this.obscure = false,
  });

  @override
  State<_DialogTextField> createState() => _DialogTextFieldState();
}

class _DialogTextFieldState extends State<_DialogTextField> {
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
