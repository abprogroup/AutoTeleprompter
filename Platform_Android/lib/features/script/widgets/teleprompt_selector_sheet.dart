import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class TelepromptSelectorSheet extends StatefulWidget {
  final String initialPath;
  const TelepromptSelectorSheet({super.key, required this.initialPath});

  @override
  State<TelepromptSelectorSheet> createState() => _TelepromptSelectorSheetState();
}

class _TelepromptSelectorSheetState extends State<TelepromptSelectorSheet> {
  late Directory _currentDir;
  List<FileSystemEntity> _entities = [];
  bool _isLoading = true;
  
  final List<String> _supportedExts = [
    'rtf', 'pdf', 'docx', 'doc', 'pages', 'txt', 'log', 'md', 'odt', 'ott', 'rtx', 'dot'
  ];

  @override
  void initState() {
    super.initState();
    _initDirectory();
  }

  Future<void> _initDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final lastPath = prefs.getString('last_picker_path');
    
    setState(() {
      // Step 2: Show most recent used folder if available
      if (lastPath != null && Directory(lastPath).existsSync()) {
        _currentDir = Directory(lastPath);
      } else {
        _currentDir = Directory(widget.initialPath);
      }
    });
    _loadEntities();
  }

  Future<void> _saveCurrentPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_picker_path', _currentDir.path);
  }

  void _loadEntities() {
    setState(() => _isLoading = true);
    try {
      final list = _currentDir.listSync().toList();
      list.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      setState(() {
        _entities = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _entities = [];
        _isLoading = false;
      });
    }
  }

  bool _isSupported(String path) {
    if (FileSystemEntity.isDirectorySync(path)) return true;
    final lower = path.toLowerCase();
    return _supportedExts.any((ext) => lower.endsWith('.$ext'));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFBF00)))
              : _entities.isEmpty 
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _entities.length,
                    itemBuilder: (ctx, i) => _buildItem(_entities[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    final isSupported = _isSupported(entity.path);
    final isDir = entity is Directory;

    return Opacity(
      // Step 3: Grey out unsupported files (APKs, PNGs, etc.)
      opacity: isSupported ? 1.0 : 0.3,
      child: ListTile(
        leading: Icon(
          isDir ? Icons.folder_rounded : (isSupported ? Icons.description_rounded : Icons.block_flipped),
          color: isDir ? Colors.amber[600] : (isSupported ? Colors.blue[400] : Colors.grey[600]),
        ),
        title: Text(name, style: TextStyle(
          color: isSupported ? Colors.white : Colors.white24,
          fontWeight: isDir ? FontWeight.bold : FontWeight.normal,
        )),
        subtitle: !isDir ? Text(isSupported ? "Selectable Script" : "Unsupported ($name)", style: TextStyle(color: Colors.white38, fontSize: 11)) : null,
        trailing: isDir ? const Icon(Icons.chevron_right, color: Colors.white24) : null,
        onTap: () async {
          if (isDir) {
            setState(() => _currentDir = entity);
            _saveCurrentPath();
            _loadEntities();
          } else if (isSupported) {
            // Step 5: Success - return to app
            Navigator.pop(context, entity as File);
          } else {
            // Step 4: Show Unsupported Dialog WITHOUT closing the selector
            await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red),
                    SizedBox(width: 10),
                    Text("Unsupported File", style: TextStyle(color: Colors.white)),
                  ],
                ),
                content: Text("The file '$name' is not a supported script format.\n\nPlease select an RTF, DOCX, or PDF file.", style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("TRY AGAIN", style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (_currentDir.path != '/')
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () {
                setState(() => _currentDir = _currentDir.parent);
                _saveCurrentPath();
                _loadEntities();
              },
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SELECT SCRIPT", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                Text(_currentDir.path, style: const TextStyle(color: Colors.white24, fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text("This folder is empty", style: TextStyle(color: Colors.white24)),
        ],
      ),
    );
  }
}
