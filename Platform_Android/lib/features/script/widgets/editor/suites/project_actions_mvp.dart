import 'package:flutter/material.dart';

// v4.0: Stable Release — Record and Settings buttons hidden (premium features)
class ProjectActionsSuite extends StatelessWidget {
  final VoidCallback onBack, onPresent, onClear, onSave, onImport, onRename;
  final VoidCallback onAddBookmark, onRemoveBookmark;
  final VoidCallback onPreviousBookmark, onNextBookmark;
  final VoidCallback? onSearch;
  final String title;

  const ProjectActionsSuite({
    super.key,
    required this.onBack,
    required this.onPresent,
    required this.onClear,
    required this.onSave,
    required this.onImport,
    required this.onRename,
    required this.onAddBookmark,
    required this.onRemoveBookmark,
    required this.onPreviousBookmark,
    required this.onNextBookmark,
    required this.title,
    this.onSearch,
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
                onPressed: onBack),
            IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Find in script',
                onPressed: onSearch),
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: onClear),
            IconButton(icon: const Icon(Icons.save_alt), onPressed: onSave),
            IconButton(
                icon: const Icon(Icons.folder_open), onPressed: onImport),
            IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: onAddBookmark),
            IconButton(
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: onRemoveBookmark),
            IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: onPreviousBookmark),
            IconButton(
                icon: const Icon(Icons.skip_next), onPressed: onNextBookmark),
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
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Color(0xFFFFBF00)),
                onPressed: onRename),
          ],
        ),
      ],
    );
  }
}
