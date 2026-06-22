import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../script/providers/script_provider.dart';
import '../../script/widgets/script_editor_screen.dart';
import '../services/deleted_scripts_service.dart';

class DeletedScriptsScreen extends ConsumerStatefulWidget {
  final DeletedScriptsService? service;

  const DeletedScriptsScreen({super.key, this.service});

  @override
  ConsumerState<DeletedScriptsScreen> createState() =>
      _DeletedScriptsScreenState();
}

class _DeletedScriptsScreenState extends ConsumerState<DeletedScriptsScreen> {
  late final DeletedScriptsService _service;
  late Future<List<DeletedScriptEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DeletedScriptsService();
    _entriesFuture = _loadEntries();
  }

  Future<List<DeletedScriptEntry>> _loadEntries() =>
      _service.listLocalDeletedScripts();

  void _refresh() {
    setState(() {
      _entriesFuture = _loadEntries();
    });
  }

  Future<void> _restore(DeletedScriptEntry entry) async {
    DeletedScriptRestoreResult? result;
    try {
      result = await _service.restoreLocalDeletedScript(entry);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not restore ${entry.displayName}.', isError: true);
      return;
    }
    if (!mounted) return;
    if (result == null) {
      _showSnack('Could not restore ${entry.displayName}.', isError: true);
      _refresh();
      return;
    }
    ref.read(scriptProvider.notifier).loadText(
          result.text,
          title: result.title,
          sourceType: result.sourceType,
          sourcePath: result.sourcePath,
          historyJson: result.historyJson,
          historyIndex: result.historyIndex,
          fontSize: result.fontSize,
          fontFamily: result.fontFamily,
          lineSpacing: result.lineSpacing,
          letterSpacing: result.letterSpacing,
          wordSpacing: result.wordSpacing,
          textAlign: result.textAlign,
          scriptBgColor: result.scriptBgColor,
          currentWordColor: result.currentWordColor,
          futureWordColor: result.futureWordColor,
        );
    if (!mounted) return;
    _showSnack('Restored ${result.title}.');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScriptEditorScreen()),
    );
  }

  Future<void> _confirmPermanentDelete(DeletedScriptEntry entry) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1F1F1F),
            title: const Text(
              'Delete forever?',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              '${entry.displayName}\n\nThis permanently removes the local '
              'deleted-script backup.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!mounted || !confirmed) return;
    try {
      await _service.permanentlyDeleteLocal(entry);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not delete ${entry.displayName}.', isError: true);
      return;
    }
    if (!mounted) return;
    _showSnack('Deleted ${entry.displayName}.');
    _refresh();
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[800] : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Deleted Scripts'),
      ),
      body: FutureBuilder<List<DeletedScriptEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFBF00)),
            );
          }
          final entries = snapshot.data ?? const <DeletedScriptEntry>[];
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No deleted local backups.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _DeletedScriptCard(
                entry: entry,
                onRestore: () => _restore(entry),
                onDelete: () => _confirmPermanentDelete(entry),
              );
            },
          );
        },
      ),
    );
  }
}

class _DeletedScriptCard extends StatelessWidget {
  final DeletedScriptEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _DeletedScriptCard({
    required this.entry,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restore_from_trash_outlined,
                  color: Color(0xFFFFBF00)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${entry.daysRemaining} days remaining',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFBF00),
                    side: const BorderSide(color: Color(0xFFFFBF00)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Delete forever',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_forever_outlined),
                color: Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
