import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../platform/file_import/platform_file_import.dart';

// v3.9.5.58: Extracted Editor Dialogs Factory
class EditorDialogs {
  static Future<String?> showConflictDialog(
      BuildContext context, String title) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(children: [
          Icon(Icons.history_edu_rounded, color: Color(0xFFFFBF00)),
          SizedBox(width: 10),
          Text("Conflict Detected", style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          "The script '$title' has been modified outside the app or has an existing history version.\n\n"
          "Would you like to discard your previous in-app edits or keep the history version?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'reload'),
            child: const Text("RELOAD & DISCARD",
                style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'history'),
            child: const Text("KEEP HISTORY",
                style: TextStyle(
                    color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Future<String?> showSaveFormatDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Save Format', style: TextStyle(color: Colors.white)),
        content: const Text('Choose format:',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'pdf'),
              child: const Text('PDF (.pdf)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'docx'),
              child: const Text('Word (.docx)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'doc'),
              child: const Text('Word 97-2003 (.doc)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'rtf'),
              child: const Text('Rich Text (.rtf)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'odt'),
              child: const Text('OpenDocument (.odt)')),
          if (PlatformFileImport.supportedExtensions.contains('pages'))
            TextButton(
                onPressed: () => Navigator.pop(context, 'pages'),
                child: const Text('Pages (.pages)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'md'),
              child: const Text('Markdown (.md)')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'txt'),
              child: const Text('Plain Text (.txt)')),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ],
      ),
    );
  }

  static Future<void> showNotSupportedDialog(
      BuildContext context, String fileName, String ext) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Text("Not Supported",
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$fileName"',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('.${ext.toUpperCase()} files cannot be used as scripts.',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            const Text('Supported formats:',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            Text(PlatformFileImport.formatsLabel,
                style: const TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK",
                  style: TextStyle(
                      color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }
}

class SaveNameDialog extends StatefulWidget {
  final TextEditingController nameCtrl;
  final List<String> usedNames;
  final String format;
  const SaveNameDialog(
      {super.key,
      required this.nameCtrl,
      required this.usedNames,
      required this.format});
  @override
  State<SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<SaveNameDialog> {
  late TextDirection _nameDirection;

  @override
  void initState() {
    super.initState();
    _nameDirection = _directionForName(widget.nameCtrl.text);
    widget.nameCtrl.addListener(_handleNameChanged);
  }

  @override
  void dispose() {
    widget.nameCtrl.removeListener(_handleNameChanged);
    super.dispose();
  }

  void _handleNameChanged() {
    final next = _directionForName(widget.nameCtrl.text);
    if (next == _nameDirection || !mounted) return;
    setState(() => _nameDirection = next);
  }

  TextDirection _directionForName(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0590 && rune <= 0x05FF) ||
          (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F)) {
        return TextDirection.rtl;
      }
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.ltr;
  }

  void _movePlainArrow(LogicalKeyboardKey key) {
    final selection = widget.nameCtrl.selection;
    final textLength = widget.nameCtrl.text.length;
    if (!selection.isValid) return;
    if (!selection.isCollapsed) {
      final collapseToEnd = _nameDirection == TextDirection.rtl
          ? key == LogicalKeyboardKey.arrowLeft
          : key == LogicalKeyboardKey.arrowRight;
      widget.nameCtrl.selection = TextSelection.collapsed(
        offset: (collapseToEnd ? selection.end : selection.start)
            .clamp(0, textLength)
            .toInt(),
      );
      return;
    }
    final delta = _nameDirection == TextDirection.rtl
        ? (key == LogicalKeyboardKey.arrowLeft ? 1 : -1)
        : (key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
    widget.nameCtrl.selection = TextSelection.collapsed(
      offset: (selection.baseOffset + delta).clamp(0, textLength).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          backgroundColor: const Color(0xFF131313),
          title: const Text('File Name', style: TextStyle(color: Colors.white)),
          content: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _SaveNameArrowIntent(LogicalKeyboardKey.arrowLeft),
              SingleActivator(LogicalKeyboardKey.arrowRight):
                  _SaveNameArrowIntent(LogicalKeyboardKey.arrowRight),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _SaveNameArrowIntent:
                    CallbackAction<_SaveNameArrowIntent>(onInvoke: (intent) {
                  _movePlainArrow(intent.key);
                  return null;
                }),
              },
              child: TextField(
                  controller: widget.nameCtrl,
                  autofocus: true,
                  textDirection: _nameDirection,
                  textAlign: _nameDirection == TextDirection.rtl
                      ? TextAlign.right
                      : TextAlign.left,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    suffixText: '.${widget.format}',
                    suffixStyle: const TextStyle(color: Colors.white54),
                  )),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                      'name': widget.nameCtrl.text.trim(),
                      'replace':
                          widget.usedNames.contains(widget.nameCtrl.text.trim())
                    }),
                child: const Text('Save'))
          ]);
}

class _SaveNameArrowIntent extends Intent {
  final LogicalKeyboardKey key;

  const _SaveNameArrowIntent(this.key);
}
