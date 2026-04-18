import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    final email = _emailCtrl.text.trim();
    final license = _licenseCtrl.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your workspace email.')));
      return;
    }

    setState(() => _isLoading = true);
    
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.login(email);
    
    bool success = false;
    if (license.isNotEmpty) {
      success = await authNotifier.activateLicense(license);
    } else if (email == 'abmpro.office@gmail.com') {
      success = true; // Admin auto-pro
    }

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('V3 Professional Suite Activated!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid License Key. Please check and try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: const Color(0xFFFFBF00), borderRadius: BorderRadius.circular(30)),
                child: const Icon(Icons.star_rounded, size: 64, color: Colors.black),
              ),
              const SizedBox(height: 32),
              Text('AutoTeleprompter', style: GoogleFonts.bebasNeue(letterSpacing: 2.0, fontSize: 32, color: const Color(0xFFFFBF00))),
              const SizedBox(height: 16),
              const Text('The ultimate tool for high-end broadcasting', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 48),
              
              _LoginTextField(controller: _emailCtrl, label: 'Workspace Email', icon: Icons.email_outlined),
              const SizedBox(height: 16),
              _LoginTextField(controller: _licenseCtrl, label: 'Professional License', icon: Icons.vpn_key_outlined, isObscure: true),
              
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleActivation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBF00),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('ACTIVATE LICENSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _showPurchaseDialog(context), 
                child: const Text('NEED A LICENSE?', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1.2)),
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
        title: const Text('Upgrade to V3 Pro', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Professional Local Remote Controller', style: TextStyle(color: Colors.white70)),
            Text('• 4K Video Support & HUD', style: TextStyle(color: Colors.white70)),
            Text('• Unlimited Cloud Sync (Coming Soon)', style: TextStyle(color: Colors.white70)),
            Text('• Advanced Eye-Contact Lens HUD', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 16),
            Text('Price: \$29.99 / Lifetime', style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Maybe Later')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mock IAP: Purchase verification starting...')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFBF00), foregroundColor: Colors.black),
            child: const Text('PURCHASE NOW'),
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

  const _LoginTextField({required this.controller, required this.label, required this.icon, this.isObscure = false});

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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
