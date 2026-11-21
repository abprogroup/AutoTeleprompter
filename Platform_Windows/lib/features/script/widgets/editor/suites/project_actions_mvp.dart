import 'package:flutter/material.dart';

// v4.0: Stable Release — Record and Settings buttons hidden (premium features)
class ProjectActionsSuite extends StatelessWidget {
  final VoidCallback onBack, onPresent, onClear, onSave, onImport, onRename;
  final VoidCallback? onSearch, onSettings, onRecord;
  final Key? saveKey, renameKey;
  final String title;
  final String? sourcePath;

  const ProjectActionsSuite({
    super.key,
    required this.onBack,
    required this.onPresent,
    required this.onClear,
    required this.onSave,
    required this.onImport,
    required this.onRename,
    required this.title,
    this.sourcePath,
    this.onSearch,
    this.onSettings,
    this.onRecord,
    this.saveKey,
    this.renameKey,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: onBack,
            ),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Find in script',
              onPressed: onSearch,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete script',
              onPressed: onClear,
            ),
            IconButton(
              key: saveKey,
              tooltip: 'Export file',
              icon: const Icon(Icons.save_alt),
              onPressed: onSave,
            ),
            IconButton(
              tooltip: 'Open script file',
              icon: const Icon(Icons.folder_open),
              onPressed: onImport,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: onSettings,
            ),
            if (onRecord != null)
              IconButton(
                icon: const Icon(Icons.videocam_outlined),
                tooltip: 'Content Creator',
                onPressed: onRecord,
              ),
          ],
        ),
        const Text(
          'Script name',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title.trim(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: renameKey,
              tooltip: 'Rename script',
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Color(0xFFFFBF00),
              ),
              onPressed: onRename,
            ),
          ],
        ),
        Tooltip(
          message: sourcePath == null
              ? 'Edits are kept in the app library. Export file lets you choose a file and folder.'
              : 'Original or last exported file: $sourcePath\nEdits are kept in the app; export to update a file.',
          child: Text(
            sourcePath == null
                ? 'App library • use Export file to choose a folder'
                : 'App library • file: ${sourcePath!.split(RegExp(r"[/\\]")).last}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
