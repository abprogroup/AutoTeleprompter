import 'package:flutter/material.dart';

class ScriptNameDialog extends StatefulWidget {
  final String initialName;
  final bool rename;
  final bool Function(String name)? nameAlreadyUsed;
  const ScriptNameDialog({
    super.key,
    this.initialName = '',
    this.rename = false,
    this.nameAlreadyUsed,
  });
  @override
  State<ScriptNameDialog> createState() => _ScriptNameDialogState();
}

class _ScriptNameDialogState extends State<ScriptNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || widget.nameAlreadyUsed?.call(name) == true) {
      setState(
        () => _error = name.isEmpty
            ? 'Enter a script name.'
            : 'This name is already in the app library. Choose another name.',
      );
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(widget.rename ? 'Rename script' : 'New script'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Script name',
                  hintText: 'e.g. Opening speech',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Stored in the app library on this device. No folder is needed. '
                'Use Export file in the editor to choose a separate file and folder.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.rename ? 'Rename' : 'Create script'),
          ),
        ],
      );
}
