import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../script/widgets/script_gallery_screen.dart';
import '../providers/beta_consent_provider.dart';

class BetaConsentGate extends ConsumerWidget {
  const BetaConsentGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(betaConsentProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Card(
              color: const Color(0xFF161616),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: const BorderSide(color: Color(0xFFFFBF00), width: 1.2),
              ),
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: consent.loaded
                    ? _ConsentContent(consent: consent)
                    : const SizedBox(
                        height: 260,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFFBF00),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentContent extends ConsumerStatefulWidget {
  final BetaConsentState consent;

  const _ConsentContent({required this.consent});

  @override
  ConsumerState<_ConsentContent> createState() => _ConsentContentState();
}

class _ConsentContentState extends ConsumerState<_ConsentContent> {
  bool _acknowledged = false;
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AutoTeleprompter Beta Privacy Notice',
            style: GoogleFonts.bebasNeue(
              color: const Color(0xFFFFBF00),
              fontSize: 30,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This beta is free to use, but participation requires diagnostic '
            'feedback data so AB Pro Group can find and fix bugs.',
            style: TextStyle(color: Colors.white, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _PolicyBox(deviceKey: widget.consent.deviceKey),
          ),
          const SizedBox(height: 18),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: _accepting
                ? null
                : (value) => setState(() => _acknowledged = value ?? false),
            activeColor: const Color(0xFFFFBF00),
            checkColor: Colors.black,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I understand and agree that beta feedback reports include my full '
              'active script and diagnostic data.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => exit(0),
                icon: const Icon(Icons.close, color: Colors.white54),
                label: const Text('Exit beta',
                    style: TextStyle(color: Colors.white70)),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _acknowledged && !_accepting ? _accept : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                    _accepting ? 'Entering beta...' : 'Accept and continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    await ref.read(betaConsentProvider.notifier).acceptCurrentPolicy();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ScriptGalleryScreen(
          initialInputShieldDuration: Duration(milliseconds: 450),
        ),
      ),
    );
  }
}

class _PolicyBox extends StatelessWidget {
  final String deviceKey;

  const _PolicyBox({required this.deviceKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _policyLine('Controller', betaFeedbackControllerName),
            _policyLine('Contact', betaFeedbackContactEmail),
            _policyLine('Device key', deviceKey, copyable: true),
            const SizedBox(height: 14),
            _paragraph(
              'What we collect: when you send feedback or confirm a crash/error '
              'report, the report includes your full active script, bug text, '
              'current app/session state, speech-to-text/editor diagnostic '
              'events, app version, platform, and this anonymous device key.',
            ),
            _paragraph(
              'What we do not do: normal app use does not continuously upload '
              'your scripts. Heavy screenshots and trace files are still created '
              'only when debug mode is enabled.',
            ),
            _paragraph(
              'Local protection: saved scripts, queued feedback reports, and '
              'debug artifacts are encrypted on this Windows account. This helps '
              'protect copied app-data files, but it cannot protect against '
              'screen recording, malware running as you, or reports you choose '
              'to send.',
            ),
            _paragraph(
              'Why we collect it: to reproduce beta bugs, group repeated reports '
              'from the same device, improve speech recognition/editor behavior, '
              'and stabilize the app before public release.',
            ),
            _paragraph(
              'Retention: beta feedback reports are kept for up to 180 days, then '
              'deleted or anonymized unless needed for an active bug investigation.',
            ),
            _paragraph(
              'Your choices: if you do not agree, you can exit the beta. To ask '
              'for deletion or privacy help, email $betaFeedbackContactEmail and '
              'include your device key or report ID.',
            ),
            _paragraph(
              'AB Pro Group does not sell beta feedback data and does not use it '
              'for third-party advertising.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _policyLine(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy device key',
              icon: const Icon(Icons.copy, color: Color(0xFFFFBF00), size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white70, height: 1.38),
        ),
      );
}
