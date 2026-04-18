import 'package:flutter/material.dart';
import '../editor_dialogs.dart';

// v4.0: Stable Release — Record and Settings buttons hidden (premium features)
class ProjectActionsSuite extends StatelessWidget {
  final VoidCallback onBack, onPresent, onClear, onSave, onImport, onRename;
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
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white70), onPressed: onBack),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: onClear),
            IconButton(icon: const Icon(Icons.save_alt), onPressed: onSave),
            IconButton(icon: const Icon(Icons.folder_open), onPressed: onImport),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(title.trim(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFFFBF00)), onPressed: onRename),
          ],
        ),
      ],
    );
  }
}
