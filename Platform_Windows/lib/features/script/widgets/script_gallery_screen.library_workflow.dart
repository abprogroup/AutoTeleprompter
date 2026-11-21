part of 'script_gallery_screen.dart';

extension _ScriptGalleryLibraryWorkflow on _ScriptGalleryScreenState {
  Future<void> _showNewScriptDialog(BuildContext context) async {
    final settings = ref.read(settingsProvider.notifier);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => ScriptNameDialog(
        nameAlreadyUsed: (name) => settings.libraryContainsScript(title: name),
      ),
    );
    if (name == null || !mounted) return;
    try {
      // A named blank is a real library record, not a transient canvas lost on exit.
      final metadata = await settings.addScriptToLibrary(title: name, text: '');
      if (!mounted) return;
      if (metadata == null) {
        _libraryMessage(
          'That name is already in the app library. Choose another name.',
        );
        return;
      }
      await settings.resetToDefaultAppearance();
      if (!mounted) return;
      ref.read(scriptProvider.notifier).loadText(
            '',
            title: name,
            sourceType: 'TEMP',
            sessionId: metadata['sessionId'] as String,
            persist: false,
          );
      await settings.activateRecentScript(metadata);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScriptEditorScreen()),
      );
    } catch (_) {
      if (mounted) {
        _libraryMessage(
          'Could not create the script. Your existing library was not replaced.',
        );
      }
    }
  }

  Future<void> _importScriptFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose folder to import scripts from',
      );
      if (path == null || !mounted) return;
      final preview = await ScriptFolderImportService.scan(path);
      if (!mounted) return;
      final library = ref.read(settingsProvider.notifier);
      final preferences = ref.read(settingsProvider);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ScriptFolderImportDialog(
          folderPath: path,
          preview: preview,
          isDuplicate: (file) => library.libraryContainsScript(
            title: file.name,
            sourcePath: file.path,
          ),
          parse: (path) => parseScriptForLibrary(File(path), preferences: preferences),
          save: (file, parsed) async =>
              await library.addScriptToLibrary(
                title: file.name,
                text: parsed.text,
                type: file.extension.toUpperCase(),
                sourcePath: file.path,
                style: parsed.style,
              ) !=
              null,
        ),
      );
    } catch (_) {
      if (mounted) {
        _libraryMessage(
          'Could not read that folder. No source files were changed.',
        );
      }
    }
  }

  void _libraryMessage(String message) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}
