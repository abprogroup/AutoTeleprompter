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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
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
            ? 'Invalid license or admin code. Please check and try again.'
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
    final code = _licenseCtrl.text.trim();

    if (email.isEmpty) {
      _showSnack('Please enter your workspace email.');
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    setState(() => _isLoading = true);
    try {
      if (!_backendCodeRequested || code.isEmpty) {
        await authNotifier.requestBackendLoginCode(email);
        await ref
            .read(settingsProvider.notifier)
            .seedDisplayNameFromEmail(email);
        setState(() {
          _backendCodeRequested = true;
          _isLoading = false;
        });
        _showSnack('Verification code sent. Check your email.');
        return;
      }

      final success = await authNotifier.verifyBackendLoginCode(
        email: email,
        code: code,
      );
      await ref.read(settingsProvider.notifier).seedDisplayNameFromEmail(email);
      setState(() => _isLoading = false);
      if (!success) {
        _showSnack('This account does not have active Pro access.');
        return;
      }
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
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showSnack(_friendlyBackendError(error));
    }
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
    if (message.contains('invalid') || message.contains('expired')) {
      return 'Invalid or expired verification code.';
    }
    if (message.contains('backend_not_configured')) {
      return 'Account backend is not configured for this build.';
    }
    return 'Account verification failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final backendMode = auth.accountBackendEnabled;
    final codeRequested = backendMode && _backendCodeRequested;
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
                label: backendMode
                    ? 'Email Verification Code'
                    : 'Professional License / Admin Code',
                icon: Icons.vpn_key_outlined,
                isObscure: true,
              ),
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
                              ? codeRequested
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
              '- Windows encrypted local script storage',
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

  const _LoginTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.isObscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
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
