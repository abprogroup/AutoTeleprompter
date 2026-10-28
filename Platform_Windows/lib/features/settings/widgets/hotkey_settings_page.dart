import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_hotkey.dart';
import '../providers/hotkey_provider.dart';

const _amber = Color(0xFFFFBF00);

/// App-wide shortcut preferences, independent of script and speech settings.
class HotkeySettingsPage extends ConsumerStatefulWidget {
  const HotkeySettingsPage({super.key});

  @override
  ConsumerState<HotkeySettingsPage> createState() => _HotkeySettingsPageState();
}

class _HotkeySettingsPageState extends ConsumerState<HotkeySettingsPage> {
  bool _busy = false;

  Future<void> _save(Future<String?> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      error = await operation();
    } catch (_) {
      error = 'Shortcut settings could not be saved. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Shortcut settings saved.')),
    );
  }

  Future<void> _change(AppHotkeyAction action) async {
    final binding = await showDialog<HotkeyBinding>(
      context: context,
      builder: (_) => _CaptureShortcutDialog(action: action),
    );
    if (!mounted || binding == null) return;
    await _save(
      () => ref.read(hotkeyProvider.notifier).setBinding(action, binding),
    );
  }

  Future<void> _resetAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Restore all default shortcuts?'),
            content: const Text(
              'This replaces your shortcut choices only. Your scripts, bookmarks, '
              'speech settings and other preferences stay unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Restore defaults'),
              ),
            ],
          ),
    );
    if (!mounted || confirmed != true) return;
    await _save(() => ref.read(hotkeyProvider.notifier).resetAll());
  }

  @override
  Widget build(BuildContext context) {
    final bindings = ref.watch(hotkeyProvider);
    if (!bindings.loaded) {
      return const Center(child: CircularProgressIndicator(color: _amber));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'KEYBOARD SHORTCUTS',
              style: TextStyle(color: _amber, fontWeight: FontWeight.bold),
            ),
            OutlinedButton.icon(
              key: const ValueKey('hotkeys-reset-all'),
              onPressed: _busy ? null : _resetAll,
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text('Restore all defaults'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Search and bookmarks work in Editor and Present. Fullscreen '
          'shortcuts work in Present only. Changes are saved on this device.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'Letters, numbers and navigation keys stay normal while editing text. '
          'Standard editing shortcuts stay unchanged. Escape closes dialogs or '
          'exits fullscreen. Shortcuts do not run behind dialogs.',
          style: TextStyle(color: Colors.white54, height: 1.4),
        ),
        const SizedBox(height: 20),
        for (final action in AppHotkeyAction.values)
          _ShortcutCard(
            action: action,
            label: bindings.labelFor(action),
            isDefault: bindings.isDefault(action),
            enabled: bindings.bindingFor(action) != null,
            busy: _busy,
            onChange: () => _change(action),
            onDisable:
                () => _save(
                  () => ref
                      .read(hotkeyProvider.notifier)
                      .setBinding(action, null),
                ),
            onReset:
                () => _save(
                  () => ref.read(hotkeyProvider.notifier).resetBinding(action),
                ),
          ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.action,
    required this.label,
    required this.isDefault,
    required this.enabled,
    required this.busy,
    required this.onChange,
    required this.onDisable,
    required this.onReset,
  });
  final AppHotkeyAction action;
  final String label;
  final bool isDefault, enabled, busy;
  final VoidCallback onChange, onDisable, onReset;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('hotkey-${action.name}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF151515),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white12),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 800 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.25;
        if (wide) {
          return Row(
            children: [
              Expanded(flex: 3, child: _description()),
              const SizedBox(width: 16),
              SizedBox(width: 145, child: _bindingLabel()),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: _actions()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _description(),
            const SizedBox(height: 12),
            _bindingLabel(),
            const SizedBox(height: 8),
            _actions(),
          ],
        );
      },
    ),
  );

  Widget _description() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        action.title,
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
      const SizedBox(height: 6),
      Text(
        action.description,
        style: const TextStyle(color: Colors.white60, height: 1.35),
      ),
    ],
  );

  Widget _bindingLabel() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: enabled ? _amber.withValues(alpha: 0.12) : Colors.black26,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: enabled ? _amber : Colors.white54,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _actions() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton.icon(
        key: ValueKey('hotkey-change-${action.name}'),
        onPressed: busy ? null : onChange,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Change'),
      ),
      TextButton(
        key: ValueKey('hotkey-disable-${action.name}'),
        onPressed: busy || !enabled ? null : onDisable,
        child: const Text('Disable'),
      ),
      TextButton(
        key: ValueKey('hotkey-reset-${action.name}'),
        onPressed: busy || isDefault ? null : onReset,
        child: const Text('Restore default'),
      ),
    ],
  );
}

class _CaptureShortcutDialog extends ConsumerStatefulWidget {
  const _CaptureShortcutDialog({required this.action});
  final AppHotkeyAction action;

  @override
  ConsumerState<_CaptureShortcutDialog> createState() =>
      _CaptureShortcutDialogState();
}

class _CaptureShortcutDialogState
    extends ConsumerState<_CaptureShortcutDialog> {
  final _captureFocus = FocusNode(debugLabel: 'Shortcut recorder');
  HotkeyBinding? _candidate;
  bool _recording = true;

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  KeyEventResult _recordKey(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      final binding = HotkeyBinding.fromEvent(event);
      if (binding != null) {
        setState(() {
          _candidate = binding;
          _recording = false;
        });
      }
    }
    // Modifier-only presses, release events and key repeats cannot leak through
    // to the editor/presenter while recording a new shortcut.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final bindings = ref.watch(hotkeyProvider);
    final candidate = _candidate;
    final conflict =
        candidate == null
            ? null
            : bindings.conflictFor(widget.action, candidate);
    final error =
        candidate?.validationError ??
        (conflict == null
            ? null
            : 'Already assigned to ${conflict.title}. Choose another shortcut '
                'or change that action first.');
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        scrollable: true,
        title: Text('Change ${widget.action.title}'),
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Press a key or shortcut, then choose Save. Single letters, '
                'numbers and navigation keys are allowed, with or without '
                'Ctrl, Alt or Shift. Typing and navigation stay normal while '
                'editing text. Escape cancels.',
              ),
              const SizedBox(height: 18),
              Focus(
                focusNode: _captureFocus,
                autofocus: true,
                onKeyEvent: _recordKey,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: _amber),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _recording ? 'Press shortcut now…' : candidate!.label,
                      style: const TextStyle(
                        color: _amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              if (!_recording) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _recording = true);
                    _captureFocus.requestFocus();
                  },
                  icon: const Icon(Icons.keyboard_outlined),
                  label: const Text('Record another shortcut'),
                ),
              ],
              if (!_recording && error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('hotkey-save'),
            onPressed:
                _recording || candidate == null || error != null
                    ? null
                    : () => Navigator.pop(context, candidate),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
