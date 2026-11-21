import 'package:flutter/material.dart';
import '../services/script_folder_import_service.dart';

class ScriptFolderImportDialog extends StatefulWidget {
  final String folderPath;
  final FolderScriptPreview preview;
  final bool Function(FolderScriptFile file) isDuplicate;
  final Future<FolderScriptContent> Function(String path) parse;
  final Future<bool> Function(
    FolderScriptFile file,
    FolderScriptContent content,
  ) save;
  const ScriptFolderImportDialog({
    super.key,
    required this.folderPath,
    required this.preview,
    required this.isDuplicate,
    required this.parse,
    required this.save,
  });
  @override
  State<ScriptFolderImportDialog> createState() =>
      _ScriptFolderImportDialogState();
}

class _ScriptFolderImportDialogState extends State<ScriptFolderImportDialog> {
  late final Set<String> _selected = widget.preview.files
      .where((file) => !widget.isDuplicate(file))
      .map((file) => file.path)
      .toSet();
  bool _running = false;
  bool _cancelled = false;
  int _completed = 0;
  FolderScriptImportReport? _report;

  Future<void> _import() async {
    setState(() {
      _running = true;
      _cancelled = false;
    });
    final report = await ScriptFolderImportService.importSelected(
      widget.preview.files
          .where((file) => _selected.contains(file.path))
          .toList(),
      parse: (file) => widget.parse(file.path),
      save: widget.save,
      isCancelled: () => _cancelled || !mounted,
      onProgress: (count, _) {
        if (mounted) setState(() => _completed = count);
      },
    );
    if (mounted) {
      setState(() {
        _report = report;
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_running,
        child: AlertDialog(
          title: const Text('Import scripts from folder'),
          content: SizedBox(
            width: 640,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.folderPath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Copies selected scripts into the app library. Originals stay unchanged. '
                  'No folder synchronization. Matching names or source files are skipped, never replaced.',
                ),
                const SizedBox(height: 8),
                Text(
                  'This folder only (no subfolders). ${ScriptFolderImportService.formatsLabel}. '
                  '${widget.preview.skippedFiles} unsupported files/links and '
                  '${widget.preview.skippedFolders} folders skipped.',
                ),
                if (widget.preview.truncated)
                  const Text(
                    'Only the first 500 folder entries were checked. Choose a smaller folder to see the rest.',
                  ),
                const Divider(),
                Expanded(
                  child: _report != null
                      ? _buildReport()
                      : ListView(
                          children: widget.preview.files.map((file) {
                            final duplicate = widget.isDuplicate(file);
                            return CheckboxListTile(
                              dense: true,
                              title: Text(file.name),
                              subtitle: duplicate
                                  ? const Text(
                                      'Already in app library — skipped',
                                    )
                                  : null,
                              value:
                                  !duplicate && _selected.contains(file.path),
                              onChanged: _running || duplicate
                                  ? null
                                  : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(file.path);
                                        } else {
                                          _selected.remove(file.path);
                                        }
                                      }),
                            );
                          }).toList(),
                        ),
                ),
                if (_running)
                  Text(
                    _cancelled
                        ? 'Stopping after the current file…'
                        : 'Importing: $_completed / ${_selected.length}',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _running
                  ? (_cancelled
                      ? null
                      : () => setState(() => _cancelled = true))
                  : () => Navigator.pop(context),
              child: Text(
                _running
                    ? 'Stop import'
                    : _report != null
                        ? 'Done'
                        : 'Cancel',
              ),
            ),
            if (!_running && _report == null)
              FilledButton(
                onPressed: _selected.isEmpty ? null : _import,
              child: Text('Import ${_selected.length} ${_selected.length == 1 ? 'script' : 'scripts'}'),
              ),
          ],
        ),
      );

  Widget _buildReport() => ListView(
        children: [
          Text('${_report!.imported} scripts copied to the app library.'),
          if (_report!.cancelled)
            const Text(
              'Import stopped. Scripts already copied remain in the library.',
            ),
          ..._report!.skipped.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(reason),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Open a script from the library when you are ready. Your active script was not changed.',
          ),
        ],
      );
}
