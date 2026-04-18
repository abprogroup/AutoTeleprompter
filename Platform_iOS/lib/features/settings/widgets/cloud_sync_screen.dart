import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

class CloudSyncScreen extends ConsumerWidget {
  const CloudSyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: Text('CLOUD MANAGEMENT', 
          style: GoogleFonts.bebasNeue(letterSpacing: 2, fontSize: 24, color: const Color(0xFFFFBF00))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sync Sources', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Connect your media storage to keep scripts in sync.', style: TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 32),
            
            _CloudOption(
              label: 'Google Drive',
              icon: Icons.add_to_drive,
              color: Colors.blue,
              onTap: () {},
            ),
            _CloudOption(
              label: 'Dropbox',
              icon: Icons.cloud_queue,
              color: Colors.blueAccent,
              onTap: () {},
            ),
            _CloudOption(
              label: 'AutoTeleprompter Cloud',
              icon: Icons.sync,
              color: const Color(0xFFFFBF00),
              onTap: () {},
            ),
            
            const SizedBox(height: 48),
            const Text('Automation', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            SwitchListTile(
              value: true,
              onChanged: (v) {},
              title: const Text('Auto-sync on save', style: TextStyle(color: Colors.white70, fontSize: 14)),
              activeColor: const Color(0xFFFFBF00),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: false,
              onChanged: (v) {},
              title: const Text('Upload recordings automatically', style: TextStyle(color: Colors.white70, fontSize: 14)),
              activeColor: const Color(0xFFFFBF00),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CloudOption({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: color, size: 28),
        title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white12, size: 16),
      ),
    );
  }
}
