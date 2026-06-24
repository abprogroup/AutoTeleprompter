import 'package:flutter/material.dart';

import '../services/remote_controller_client.dart';

/// In-app remote controller: drive another device that is hosting the
/// AutoTeleprompter remote server over the same Wi-Fi. Paste the host's URL and
/// PIN (from its Settings → Remote tab) and use the command pad.
class RemoteControllerScreen extends StatefulWidget {
  const RemoteControllerScreen({super.key});

  @override
  State<RemoteControllerScreen> createState() => _RemoteControllerScreenState();
}

class _RemoteControllerScreenState extends State<RemoteControllerScreen> {
  final _client = RemoteControllerClient();
  final _urlController = TextEditingController();
  final _pinController = TextEditingController();

  static const _accent = Color(0xFFFFBF00);

  @override
  void dispose() {
    _client.dispose();
    _urlController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    await _client.connect(
      target: _urlController.text,
      pinOverride: _pinController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Control Another Device'),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _client,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusBanner(),
                  const SizedBox(height: 18),
                  if (!_client.isConnected) ..._connectForm(),
                  if (_client.isConnected) ..._commandPad(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final status = _client.status;
    final (color, icon) = switch (status) {
      RemoteControllerStatus.connected => (_accent, Icons.link_rounded),
      RemoteControllerStatus.connecting => (
          Colors.white70,
          Icons.sync_rounded
        ),
      RemoteControllerStatus.error => (Colors.redAccent, Icons.error_outline),
      RemoteControllerStatus.idle => (Colors.white38, Icons.link_off_rounded),
    };
    final text = _client.message.isNotEmpty
        ? _client.message
        : 'Enter the host URL and PIN shown on the other device.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  List<Widget> _connectForm() {
    return [
      const Text(
        'On the device you want to control, open Settings → Remote, start '
        'hosting, and read its URL + PIN.',
        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.3),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _urlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        style: const TextStyle(color: Colors.white),
        decoration: _fieldDecoration('Host URL', 'http://192.168.0.10:8080'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pinController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        style: const TextStyle(color: Colors.white, letterSpacing: 4),
        decoration: _fieldDecoration('PIN', '123456'),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _client.status == RemoteControllerStatus.connecting
            ? null
            : _connect,
        icon: const Icon(Icons.cast_connected_rounded),
        label: const Text('Connect'),
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];
  }

  List<Widget> _commandPad() {
    return [
      _commandButton('START / STOP', 'TOGGLE', primary: true),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _commandButton('SLOWER', 'SLOWER')),
          const SizedBox(width: 10),
          Expanded(child: _commandButton('FASTER', 'FASTER')),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _commandButton('AUTO', 'MODE_AUTO')),
          const SizedBox(width: 10),
          Expanded(child: _commandButton('MANUAL', 'MODE_MANUAL')),
        ],
      ),
      const SizedBox(height: 10),
      _commandButton('RESET POSITION', 'RESET'),
      const SizedBox(height: 18),
      const Text('BOOKMARKS',
          style: TextStyle(color: Colors.white38, letterSpacing: 1.5)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _commandButton('PREVIOUS', 'BOOKMARK_PREVIOUS')),
          const SizedBox(width: 10),
          Expanded(child: _commandButton('NEXT', 'BOOKMARK_NEXT')),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: _commandButton('ADD MARK', 'BOOKMARK_ADD')),
          const SizedBox(width: 10),
          Expanded(child: _commandButton('REMOVE MARK', 'BOOKMARK_REMOVE')),
        ],
      ),
      const SizedBox(height: 18),
      _commandButton('INVERT SCRIPT COLORS', 'INVERT_COLORS'),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () => _client.disconnect(),
        icon: const Icon(Icons.link_off_rounded),
        label: const Text('Disconnect'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];
  }

  Widget _commandButton(String label, String command, {bool primary = false}) {
    return FilledButton(
      onPressed: () => _client.sendCommand(command),
      style: FilledButton.styleFrom(
        backgroundColor: primary ? _accent : const Color(0xFF1A1A1A),
        foregroundColor: primary ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: primary
            ? null
            : BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
      labelStyle: const TextStyle(color: Colors.white54),
      hintStyle: const TextStyle(color: Colors.white24),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent),
      ),
    );
  }
}
