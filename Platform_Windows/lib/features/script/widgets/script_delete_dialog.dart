import 'dart:io';

import 'package:flutter/material.dart';

class ScriptDeleteChoice {
  final bool deleteSourceFile;

  const ScriptDeleteChoice({required this.deleteSourceFile});
}

Future<ScriptDeleteChoice?> showScriptDeleteDialog(
  BuildContext context, {
  required String title,
  String? sourcePath,
}) async {
  final trimmedPath = sourcePath?.trim() ?? '';
  final canDeleteSource =
      trimmedPath.isNotEmpty && await File(trimmedPath).exists();
  var deleteSourceFile = false;

  if (!context.mounted) return null;
  return showDialog<ScriptDeleteChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
            SizedBox(width: 10),
            Text(
              'Delete script?',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$title"',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This removes the script from the app and Recent Activity. '
              'If Local Backup is configured, a deleted-script backup is kept '
              'for 30 days.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: canDeleteSource && deleteSourceFile,
              onChanged: canDeleteSource
                  ? (value) => setDialogState(
                        () => deleteSourceFile = value ?? false,
                      )
                  : null,
              activeColor: const Color(0xFFFFBF00),
              checkColor: Colors.black,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Delete file also from folder',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                canDeleteSource
                    ? trimmedPath
                    : 'No original folder file is linked to this script.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              ScriptDeleteChoice(
                deleteSourceFile: canDeleteSource && deleteSourceFile,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
}
