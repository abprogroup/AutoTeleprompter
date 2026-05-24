import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../script/providers/script_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../teleprompter/providers/teleprompter_provider.dart';
import '../providers/beta_consent_provider.dart';
import '../services/feedback_report_service.dart';
import '../services/lightweight_diagnostics.dart';

class FeedbackReportScreen extends ConsumerStatefulWidget {
  const FeedbackReportScreen({super.key});

  @override
  ConsumerState<FeedbackReportScreen> createState() =>
      _FeedbackReportScreenState();
}

class _FeedbackReportScreenState extends ConsumerState<FeedbackReportScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _stepsCtrl = TextEditingController();
  String _category = 'Bug';
  String _severity = 'Normal';
  bool _sending = false;
  bool _outboxBusy = false;
  int _pendingReports = 0;

  @override
  void initState() {
    super.initState();
    LightweightDiagnostics.instance.record(
      'feedback',
      'feedback screen opened',
    );
    _refreshPendingReports();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _stepsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final script = ref.watch(scriptProvider);
    final consent = ref.watch(betaConsentProvider);
    final scriptSummary = script == null
        ? 'No active script'
        : '${script.title} - ${script.rawText.length} characters';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Send Beta Feedback',
          style: GoogleFonts.bebasNeue(
            color: const Color(0xFFFFBF00),
            fontSize: 24,
            letterSpacing: 1.4,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          _notice(scriptSummary, consent.deviceKey),
          const SizedBox(height: 18),
          if (_pendingReports > 0) ...[
            _outboxCard(),
            const SizedBox(height: 18),
          ],
          _choiceRow(
            label: 'Category',
            value: _category,
            values: const [
              'Bug',
              'Speech-to-text system',
              'Editor',
              'Presenter',
              'Crash',
              'Other'
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          _choiceRow(
            label: 'Severity',
            value: _severity,
            values: const ['Low', 'Normal', 'High', 'Blocking'],
            onChanged: (v) => setState(() => _severity = v),
          ),
          const SizedBox(height: 12),
          _field(_titleCtrl, 'Short title', maxLines: 1),
          const SizedBox(height: 12),
          _field(_descriptionCtrl, 'What happened?', maxLines: 5),
          const SizedBox(height: 12),
          _field(_stepsCtrl, 'Steps to reproduce', maxLines: 5),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(_sending ? 'Preparing report...' : 'Send feedback'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String scriptSummary, String deviceKey) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFFFBF00).withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This beta feedback report includes your full active script and diagnostic data.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text('Active script: $scriptSummary',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text('Device key: $deviceKey',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _outboxCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending feedback reports: $_pendingReports',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'These reports are saved locally because the feedback service was unavailable.',
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _outboxBusy ? null : _retryPendingReports,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Retry'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _outboxBusy ? null : _deletePendingReports,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choiceRow({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
  }) {
    return InputDecorator(
      decoration: _decoration(label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1E1E1E),
          isExpanded: true,
          items: values
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {required int maxLines}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF171717),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFFBF00)),
        ),
      );

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty ||
        _descriptionCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title and description first.')),
      );
      return;
    }

    setState(() => _sending = true);
    final report = _buildReport();
    final result = await FeedbackReportService().submit(report);
    if (!mounted) return;
    setState(() => _sending = false);
    await _refreshPendingReports();
    if (!mounted) return;
    LightweightDiagnostics.instance.record(
      'feedback',
      result.sent ? 'feedback sent' : 'feedback queued',
      data: {'reportId': result.reportId, 'queued': result.queued},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.sent ? Colors.green[800] : Colors.orange[800],
      ),
    );
    if (!mounted) return;
    if (result.sent) Navigator.pop(context);
  }

  Future<void> _refreshPendingReports() async {
    final count = await FeedbackReportService().pendingReportCount();
    if (!mounted) return;
    setState(() => _pendingReports = count);
  }

  Future<void> _retryPendingReports() async {
    setState(() => _outboxBusy = true);
    final result = await FeedbackReportService().retryPendingReports();
    if (!mounted) return;
    setState(() {
      _outboxBusy = false;
      _pendingReports = result.remaining;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _deletePendingReports() async {
    setState(() => _outboxBusy = true);
    final deleted = await FeedbackReportService().deletePendingReports();
    if (!mounted) return;
    setState(() {
      _outboxBusy = false;
      _pendingReports = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted $deleted pending report(s).')),
    );
  }

  Map<String, Object?> _buildReport() {
    final script = _safeRead(() => ref.read(scriptProvider));
    final settings = ref.read(settingsProvider);
    final consent = ref.read(betaConsentProvider);
    final reportId = 'rpt_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    return {
      'schemaVersion': 1,
      'reportId': reportId,
      'deviceKey': consent.deviceKey,
      'consentVersion': consent.acceptedPolicyVersion,
      'appVersion': betaAppVersion,
      'platform': Platform.operatingSystem,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'userText': {
        'category': _category,
        'severity': _severity,
        'title': _titleCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'steps': _stepsCtrl.text.trim(),
      },
      'activeScript': script == null
          ? null
          : {
              'title': script.title,
              'sourceType': script.sourceType,
              'sessionId': script.sessionId,
              'isRtl': script.isRtl,
              'rawText': script.rawText,
              'wordCount': script.words.where((w) => !w.isNewline).length,
            },
      'diagnostics': {
        'teleprompter': _readTeleprompterDiagnostics(),
        'settings': {
          'languageMode': settings.languageMode,
          'scrollMode': settings.scrollMode,
          'sttEngine': settings.sttEngine,
          'sttInputDeviceLabel': settings.sttInputDeviceLabel,
          'sttVisibleSkipEnabled': settings.sttVisibleSkipEnabled,
        },
        'ringBuffer': LightweightDiagnostics.instance.snapshot(
          budgetBytes: 96 * 1024,
          stackTraceLimit: 2000,
        ),
      },
    };
  }

  Map<String, Object?> _readTeleprompterDiagnostics() {
    try {
      final teleprompter = ref.read(teleprompterProvider);
      return {
        'available': true,
        'confirmedWordIndex': teleprompter.confirmedWordIndex,
        'isListening': teleprompter.isListening,
        'isStarting': teleprompter.isStarting,
        'hasError': teleprompter.hasError,
        'statusMessage': teleprompter.statusMessage,
        'debugLogsTail': _tail(teleprompter.debugLogs, 20),
      };
    } catch (error) {
      LightweightDiagnostics.instance.record(
        'feedback',
        'teleprompter snapshot unavailable',
        data: {'error': error.toString()},
      );
      return {
        'available': false,
        'snapshotError': error.toString(),
      };
    }
  }

  T? _safeRead<T>(T Function() read) {
    try {
      return read();
    } catch (error) {
      LightweightDiagnostics.instance.record(
        'feedback',
        'provider snapshot unavailable',
        data: {'error': error.toString()},
      );
      return null;
    }
  }

  List<T> _tail<T>(List<T> items, int count) {
    if (items.length <= count) return List<T>.from(items);
    return items.sublist(items.length - count);
  }
}
