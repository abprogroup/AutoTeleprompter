import 'dart:async';
import 'dart:io';

import 'update_check_service.dart';

class UpdateInstallService {
  static const _updateTempFolderName = 'AutoTeleprompter Updates';

  static Future<void> cleanupCompletedUpdateTemp({
    Directory? updatesRoot,
    String? resolvedExecutable,
  }) async {
    final root = updatesRoot ?? await _updatesDirectory();
    if (!await root.exists()) return;
    final rootPath = _normalizedPath(root.path);
    final executablePath = _normalizedPath(
      resolvedExecutable ?? Platform.resolvedExecutable,
    );
    if (executablePath == rootPath || executablePath.startsWith('$rootPath/')) {
      return;
    }
    final successFile = File(
      _joinPath(root.path, 'install_autoteleprompter_update.success'),
    );
    if (!await successFile.exists()) return;
    try {
      await root.delete(recursive: true);
    } catch (_) {
      // Cleanup is best-effort; a running installer script may still hold a file.
    }
  }

  Future<void> installDownloadedUpdate(
    File packageFile,
    UpdateCheckResult result,
  ) async {
    if (Platform.isMacOS) {
      await _installMacOSUpdate(packageFile, result);
      return;
    }
    throw UnsupportedError(
      'Automatic update install is only wired on macOS builds.',
    );
  }

  Future<void> _installMacOSUpdate(
    File packageFile,
    UpdateCheckResult result,
  ) async {
    if (!await packageFile.exists()) {
      throw StateError('Downloaded update package is missing.');
    }

    final currentApp = _currentMacAppBundle();
    await _validateMacOSInstallTarget(currentApp);
    await _verifyMacOSInstallWritable(currentApp);
    final stageRoot = await _createStageDirectory(result);
    await _extractMacOSPackage(packageFile, stageRoot);
    final updateApp = await _findMacOSUpdateApp(stageRoot);
    final handoff = await _writeMacOSHandoffScript(
      updateApp: updateApp,
      currentApp: currentApp,
    );

    if (await handoff.startedFile.exists()) await handoff.startedFile.delete();
    if (await handoff.logFile.exists()) await handoff.logFile.delete();
    if (await handoff.successFile.exists()) await handoff.successFile.delete();
    if (await handoff.failedFile.exists()) await handoff.failedFile.delete();

    await _startMacOSInstallerHandoff(handoff);
    final installerStarted = await _waitForInstallerStart(handoff.startedFile);
    if (!installerStarted) {
      throw StateError(
        'Update installer did not start. AutoTeleprompter stayed open so '
        'the current build was not lost.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  Future<Directory> _createStageDirectory(UpdateCheckResult result) async {
    final root = await _updatesDirectory();
    await root.create(recursive: true);
    final version = _safeName(result.latestVersion ?? 'update');
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
          RegExp(r'[:.]'),
          '-',
        );
    final stage = Directory(_joinPath(root.path, 'stage_${version}_$stamp'));
    if (await stage.exists()) await stage.delete(recursive: true);
    await stage.create(recursive: true);
    return stage;
  }

  Future<void> _extractMacOSPackage(
    File packageFile,
    Directory stageRoot,
  ) async {
    final result = await Process.run(
      '/usr/bin/ditto',
      ['-x', '-k', packageFile.path, stageRoot.path],
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Could not extract macOS update package: ${result.stderr}',
      );
    }
  }

  Directory _currentMacAppBundle() {
    var directory = File(Platform.resolvedExecutable).parent;
    while (true) {
      if (directory.path.endsWith('.app')) return directory;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw StateError('Could not locate the running macOS app bundle.');
  }

  Future<Directory> _findMacOSUpdateApp(Directory stageRoot) async {
    final executableName = _baseName(Platform.resolvedExecutable);
    await for (final entity in stageRoot.list(recursive: true)) {
      if (entity is! Directory || !entity.path.endsWith('.app')) continue;
      final executable = File(
        _joinPath(
          _joinPath(_joinPath(entity.path, 'Contents'), 'MacOS'),
          executableName,
        ),
      );
      if (await executable.exists()) return entity;
    }
    throw StateError('Update package does not contain a macOS app bundle.');
  }

  Future<void> _validateMacOSInstallTarget(Directory currentApp) async {
    final updatesRoot = await _updatesDirectory();
    final currentPath = _normalizedPath(currentApp.path);
    final updatesPath = _normalizedPath(updatesRoot.path);
    if (currentPath == updatesPath || currentPath.startsWith('$updatesPath/')) {
      throw StateError(
        'AutoTeleprompter is running from a temporary update folder. '
        'Open the app from a release folder or Applications before installing '
        'another update.',
      );
    }
  }

  Future<void> _verifyMacOSInstallWritable(Directory currentApp) async {
    final parent = currentApp.parent;
    final probe = File(
      _joinPath(
        parent.path,
        '.autoteleprompter_update_write_test_$pid',
      ),
    );
    try {
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
    } on FileSystemException catch (error) {
      throw StateError(
        'AutoTeleprompter cannot install updates into ${parent.path}. '
        'Move the app to a writable release folder or Applications copy and '
        'try again. Details: ${error.message}',
      );
    }
  }

  Future<_MacUpdateHandoff> _writeMacOSHandoffScript({
    required Directory updateApp,
    required Directory currentApp,
  }) async {
    final root = await _updatesDirectory();
    await root.create(recursive: true);
    final script =
        File(_joinPath(root.path, 'install_autoteleprompter_update.sh'));
    final log =
        File(_joinPath(root.path, 'install_autoteleprompter_update.log'));
    final started = File(
      _joinPath(root.path, 'install_autoteleprompter_update.started'),
    );
    final success = File(
      _joinPath(root.path, 'install_autoteleprompter_update.success'),
    );
    final failed = File(
      _joinPath(root.path, 'install_autoteleprompter_update.failed'),
    );
    final backupRoot = Directory(_joinPath(root.path, 'rollback'));
    final content = '''
#!/bin/bash
set -euo pipefail

source_app=${_shString(updateApp.path)}
target_app=${_shString(currentApp.path)}
pid_to_wait=$pid
log=${_shString(log.path)}
started=${_shString(started.path)}
success=${_shString(success.path)}
failed=${_shString(failed.path)}
backup_root=${_shString(backupRoot.path)}
backup_app=""
new_app="\$target_app.updating"

mkdir -p "\$(dirname "\$log")" "\$backup_root"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "\$started"

log_msg() {
  printf '[%s] %s\\n' "\$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "\$1" >> "\$log"
}

run_cmd() {
  log_msg "\$1"
  shift
  "\$@" >> "\$log" 2>&1
}

finish() {
  status=\$?
  if [ "\$status" -ne 0 ]; then
    log_msg "Update install failed with status \$status."
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "\$failed"
    rm -rf "\$new_app" >/dev/null 2>&1 || true
    if [ -n "\$backup_app" ] && [ -d "\$backup_app" ]; then
      log_msg "Attempting rollback from \$backup_app."
      rm -rf "\$target_app"
      /usr/bin/ditto "\$backup_app" "\$target_app" || true
    fi
    if [ -d "\$target_app" ]; then
      log_msg "Relaunching existing AutoTeleprompter after failed update."
      /usr/bin/open -n "\$target_app" || true
    fi
  fi
  exit "\$status"
}
trap finish EXIT

log_msg "Waiting for AutoTeleprompter process \$pid_to_wait to exit."
for _ in {1..60}; do
  if ! kill -0 "\$pid_to_wait" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if kill -0 "\$pid_to_wait" >/dev/null 2>&1; then
  log_msg "Stopping AutoTeleprompter process \$pid_to_wait."
  kill "\$pid_to_wait" >/dev/null 2>&1 || true
  for _ in {1..10}; do
    if ! kill -0 "\$pid_to_wait" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi
if kill -0 "\$pid_to_wait" >/dev/null 2>&1; then
  log_msg "Force-stopping AutoTeleprompter process \$pid_to_wait."
  kill -9 "\$pid_to_wait" >/dev/null 2>&1 || true
  sleep 1
fi

if [ ! -d "\$source_app" ]; then
  log_msg "Staged app is missing: \$source_app"
  exit 1
fi

run_cmd "Preparing replacement app at \$new_app." /bin/rm -rf "\$new_app"
run_cmd "Copying update from \$source_app to \$new_app." /usr/bin/ditto "\$source_app" "\$new_app"
/usr/bin/xattr -dr com.apple.quarantine "\$new_app" >> "\$log" 2>&1 || true
/bin/chmod -R u+rwX "\$new_app" >> "\$log" 2>&1 || true

if [ -d "\$target_app" ]; then
  backup_app="\$backup_root/rollback_\$(date -u +%Y%m%d_%H%M%S).app"
  run_cmd "Backing up current app to \$backup_app." /usr/bin/ditto "\$target_app" "\$backup_app"
  run_cmd "Removing current app at \$target_app." /bin/rm -rf "\$target_app"
fi

run_cmd "Moving replacement app into place at \$target_app." /bin/mv "\$new_app" "\$target_app"

date -u +"%Y-%m-%dT%H:%M:%SZ" > "\$success"
log_msg "Relaunching updated AutoTeleprompter."
if ! /usr/bin/open -n "\$target_app" >> "\$log" 2>&1; then
  log_msg "Updated app installed, but relaunch failed. Leaving app in place."
fi
trap - EXIT
exit 0
''';
    await script.writeAsString(content, flush: true);
    await Process.run('/bin/chmod', ['+x', script.path]);
    return _MacUpdateHandoff(
      scriptFile: script,
      logFile: log,
      startedFile: started,
      successFile: success,
      failedFile: failed,
    );
  }

  Future<bool> _waitForInstallerStart(File startedFile) async {
    for (var i = 0; i < 25; i++) {
      if (await startedFile.exists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _startMacOSInstallerHandoff(_MacUpdateHandoff handoff) async {
    await Process.start(
      '/bin/bash',
      [handoff.scriptFile.path],
      mode: ProcessStartMode.detached,
      workingDirectory: handoff.scriptFile.parent.path,
    );
  }

  static Future<Directory> _updatesDirectory() async {
    if (Platform.isMacOS) {
      final tmp = Platform.environment['TMPDIR']?.trim();
      final root = Directory(
        tmp == null || tmp.isEmpty ? Directory.systemTemp.path : tmp,
      );
      return Directory(_joinPath(root.path, _updateTempFolderName));
    }
    throw UnsupportedError('Update temp folders are only wired on macOS.');
  }

  static String _safeName(String value) {
    return value
        .trim()
        .replaceAll('+', '-')
        .replaceAll(RegExp(r'[<>:"/\\|?*\s]+'), '_');
  }

  static String _shString(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  static String _normalizedPath(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  static String _joinPath(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) return '$left$right';
    return '$left${Platform.pathSeparator}$right';
  }
}

class _MacUpdateHandoff {
  final File scriptFile;
  final File logFile;
  final File startedFile;
  final File successFile;
  final File failedFile;

  const _MacUpdateHandoff({
    required this.scriptFile,
    required this.logFile,
    required this.startedFile,
    required this.successFile,
    required this.failedFile,
  });
}
