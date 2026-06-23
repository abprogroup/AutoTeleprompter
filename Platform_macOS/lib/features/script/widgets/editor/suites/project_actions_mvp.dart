import 'package:flutter/material.dart';

// v4.0: Stable Release — Record and Settings buttons hidden (premium features)
class ProjectActionsSuite extends StatelessWidget {
  final VoidCallback onBack, onPresent, onClear, onSave, onImport, onRename;
  final VoidCallback? onSearch, onSettings, onRecord;
  final Key? saveKey, renameKey;
  final String title;

  const ProjectActionsSuite({
    super.key,
    required this.onBack,
    required this.onPresent,
    required this.onClear,
    required this.onSave,
    required this.onImport,
    required this.onRename,
    required this.title,
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
                tooltip: 'Back to lobby',
                onPressed: onBack),
            IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Find in script',
                onPressed: onSearch),
            IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete script',
                onPressed: onClear),
            IconButton(
              key: saveKey,
              icon: const Icon(Icons.save_alt),
              tooltip: 'Save script',
              onPressed: onSave,
            ),
            IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Load script',
                onPressed: onImport),
            IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: onSettings),
            if (onRecord != null)
              IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Content Creator',
                  onPressed: onRecord),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
                child: Text(title.trim(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 20),
                    overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            IconButton(
                key: renameKey,
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Color(0xFFFFBF00)),
                tooltip: 'Rename script',
                onPressed: onRename),
          ],
        ),
      ],
    );
  }
}
