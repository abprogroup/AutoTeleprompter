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
  bool _speechAcknowledged = false;
  bool _cloudAcknowledged = false;
  bool _accepting = false;
  late int _stepIndex;

  @override
  void initState() {
    super.initState();
    _stepIndex = widget.consent.hasAcceptedFeedbackPolicy
        ? (widget.consent.hasAcceptedSpeechDisclosure ? 2 : 1)
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final isSpeechStep = _stepIndex == 1;
    final isCloudStep = _stepIndex == 2;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(currentStep: _stepIndex + 1, totalSteps: 3),
          const SizedBox(height: 8),
          Text(
            isCloudStep
                ? 'Cloud Storage Disclosure'
                : isSpeechStep
                    ? 'Speech-To-Text Disclosure'
                    : 'AutoTeleprompter Beta Privacy Notice',
            style: GoogleFonts.bebasNeue(
              color: const Color(0xFFFFBF00),
              fontSize: 30,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isCloudStep
                ? 'Cloud features can connect to personal storage providers or '
                    'future AutoTeleprompter managed storage. You must understand '
                    'where script and recording files may be stored before using '
                    'this app.'
                : isSpeechStep
                    ? 'Speech-to-text can listen to your microphone to advance '
                        'the prompter. Depending on the engine and platform, audio '
                        'may be processed on-device or by the platform speech '
                        'provider.'
                    : 'This beta is free to use, but participation requires '
                        'diagnostic feedback data so AB Pro Group can find and '
                        'fix bugs.',
            style: const TextStyle(
                color: Colors.white, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isCloudStep
                ? const _CloudDisclosureBox()
                : isSpeechStep
                    ? const _SpeechDisclosureBox()
                    : _PolicyBox(deviceKey: widget.consent.deviceKey),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: isCloudStep
                ? _cloudAcknowledged
                : isSpeechStep
                    ? _speechAcknowledged
                    : _acknowledged,
            onChanged: _accepting
                ? null
                : (value) => setState(() {
                      if (isCloudStep) {
                        _cloudAcknowledged = value ?? false;
                      } else if (isSpeechStep) {
                        _speechAcknowledged = value ?? false;
                      } else {
                        _acknowledged = value ?? false;
                      }
                    }),
            activeColor: const Color(0xFFFFBF00),
            checkColor: Colors.black,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              isCloudStep
                  ? 'I understand and agree to the cloud storage disclosure for '
                      'this app.'
                  : isSpeechStep
                      ? 'I understand and agree to the speech-to-text '
                          'disclosure for this app.'
                      : 'I understand and agree that beta feedback reports '
                          'include my full active script and diagnostic data.',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final exitButton = TextButton.icon(
                onPressed: SystemNavigator.pop,
                icon: const Icon(Icons.close, color: Colors.white54),
                label: const Text(
                  'Exit beta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70),
                ),
              );
              final backButton = TextButton(
                onPressed: _accepting || _stepIndex == 0
                    ? null
                    : () => setState(() => _stepIndex = _stepIndex - 1),
                child: const Text('Back'),
              );
              final acceptButton = ElevatedButton.icon(
                onPressed: _canContinue(isSpeechStep) ? _accept : null,
                icon: Icon(
                  isCloudStep || isSpeechStep
                      ? Icons.check_circle_outline
                      : Icons.arrow_forward_rounded,
                ),
                label: Text(
                  _accepting
                      ? 'Entering beta...'
                      : isCloudStep
                          ? 'Accept and continue'
                          : isSpeechStep
                              ? 'Accept speech disclosure'
                              : 'Accept feedback notice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFBF00),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: double.infinity, child: acceptButton),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: exitButton),
                        if (_stepIndex > 0) backButton,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: exitButton,
                    ),
                  ),
                  if (_stepIndex > 0) backButton,
                  const SizedBox(width: 12),
                  Flexible(
                    child: SizedBox(
                      width: double.infinity,
                      child: acceptButton,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool _canContinue(bool isSpeechStep) {
    if (_accepting) return false;
    if (_stepIndex == 2) return _cloudAcknowledged;
    return isSpeechStep ? _speechAcknowledged : _acknowledged;
  }

  Future<void> _accept() async {
    final notifier = ref.read(betaConsentProvider.notifier);
    if (_stepIndex == 0) {
      setState(() => _accepting = true);
      await notifier.acceptFeedbackPolicy();
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _stepIndex = 1;
      });
      return;
    }

    if (_stepIndex == 1) {
      setState(() => _accepting = true);
      await notifier.acceptSpeechDisclosure();
      if (!mounted) return;
      setState(() {
        _accepting = false;
        _stepIndex = 2;
      });
      return;
    }

    setState(() => _accepting = true);
    await notifier.acceptCloudDisclosure();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const ScriptGalleryScreen(),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepHeader({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= totalSteps; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color:
                    i <= currentStep ? const Color(0xFFFFBF00) : Colors.white12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          if (i != totalSteps) const SizedBox(width: 8),
        ],
        const SizedBox(width: 12),
        Text(
          '$currentStep/$totalSteps',
          style: const TextStyle(
            color: Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
              'Local protection: queued feedback reports are encrypted with '
              'platform secure storage before retry. Full script-at-rest '
              'encryption is platform-specific and will be completed before '
              'public beta parity. This cannot protect against screen recording, '
              'malware running as you, or reports you choose to send.',
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

class _SpeechDisclosureBox extends StatelessWidget {
  const _SpeechDisclosureBox();

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
            _paragraph(
              'When speech-to-text is enabled, AutoTeleprompter listens to the '
              'selected microphone so it can match spoken words to the script '
              'and move the reading position.',
            ),
            _paragraph(
              'Processing location depends on the selected engine, language, '
              'operating system, and installed speech packs. Some recognition '
              'may happen on this device. Some recognition may be processed by '
              'the platform speech provider, such as Google, Microsoft, Apple, '
              'or the browser speech service.',
            ),
            _paragraph(
              'This app uses speech results to control the prompter. It does '
              'not intentionally send continuous microphone audio to AB Pro '
              'Group servers for normal speech-to-text operation.',
            ),
            _paragraph(
              'If you send feedback while speech-to-text is active, the '
              'feedback report may include speech-to-text diagnostic events and '
              'recent recognized text needed to reproduce bugs.',
            ),
            _paragraph(
              'Do not use speech-to-text with private, legal, medical, or '
              'confidential speech unless you are comfortable with the selected '
              'platform speech provider processing it.',
            ),
            _paragraph(
              'Future work will improve fully offline speech-to-text so '
              'users who do not want online speech providers can use an offline '
              'engine path without accepting online speech processing.',
            ),
          ],
        ),
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

class _CloudDisclosureBox extends StatelessWidget {
  const _CloudDisclosureBox();

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
            _paragraph(
              'AutoTeleprompter cloud features are planned for syncing scripts, '
              'metadata, bookmarks, reading positions, recordings, and account '
              'state across devices.',
            ),
            _paragraph(
              'Personal cloud providers, such as Google Drive and Dropbox, use '
              'the user\'s own provider account and are not '
              'AutoTeleprompter-hosted storage. Provider terms, privacy rules, '
              'quotas, and availability may apply.',
            ),
            _paragraph(
              'AutoTeleprompter Cloud is planned as a separate managed service '
              'using AutoTeleprompter account identity and company-managed '
              'storage. It may be a paid feature because storage, bandwidth, '
              'backup, and support create ongoing company cost.',
            ),
            _paragraph(
              'Do not place private, legal, medical, or confidential scripts in '
              'cloud sync unless you are comfortable with the selected provider '
              'or managed AutoTeleprompter Cloud storing those files.',
            ),
            _paragraph(
              'Current builds may show cloud connection options before the '
              'sync backend is fully active. Features marked planned or coming '
              'soon do not upload normal scripts until the provider connection '
              'and sync flow are implemented and enabled.',
            ),
          ],
        ),
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
