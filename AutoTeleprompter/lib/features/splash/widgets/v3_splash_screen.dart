import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../script/widgets/script_gallery_screen.dart';

class V3SplashScreen extends StatefulWidget {
  const V3SplashScreen({super.key});

  @override
  State<V3SplashScreen> createState() => _V3SplashScreenState();
}

class _V3SplashScreenState extends State<V3SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ScriptGalleryScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFBF00), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFBF00).withOpacity(0.2),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFFFFBF00),
                size: 64,
              ),
            )
            .animate()
            .scale(duration: 800.ms, curve: Curves.elasticOut)
            .shimmer(delay: 1.seconds, duration: 1.5.seconds),
            
            const SizedBox(height: 32),
            
            Text(
              'AUTOTELEPROMPTER',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            )
            .animate()
            .fadeIn(delay: 400.ms)
            .slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }
}
