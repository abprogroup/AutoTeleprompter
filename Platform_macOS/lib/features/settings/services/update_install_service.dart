import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';

import 'update_check_service.dart';

class UpdateInstallService {
  static const _updateTempFolderName = 'AutoTeleprompter Updates';

  static Future<void> cleanupCompletedUpdateTemp() async {
    final root = await _updatesDirectory();
    if (!await root.exists()) return;
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
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Automatic update install is only wired on desktop builds.',
      );
    }
    if (!await packageFile.exists()) {
      throw StateError('Downloaded update package is missing.');
    }

    final currentExe = File(Platform.resolvedExecutable);
    final installDir = currentExe.parent;
    final exeName = _baseName(currentExe.path);
    final stageRoot = await _createStageDirectory(result);
    await _extractPackage(packageFile, stageRoot);
    final updateRoot = await _findUpdateRoot(stageRoot, exeName);
    final handoff = await _writeHandoffScript(
      updateRoot: updateRoot,
      installDir: installDir,
      exeName: exeName,
    );

    if (await handoff.startedFile.exists()) {
      await handoff.startedFile.delete();
    }
    if (await handoff.logFile.exists()) {
      await handoff.logFile.delete();
    }
    if (await handoff.successFile.exists()) {
      await handoff.successFile.delete();
    }

    await _startInstallerHandoff(handoff);
    var installerStarted = await _waitForInstallerStart(handoff.startedFile);
    if (!installerStarted) {
      await _startInstallerHandoffViaCmd(handoff);
      installerStarted = await _waitForInstallerStart(handoff.startedFile);
    }
    if (!installerStarted) {
      throw StateError(
        'Update installer did not start. AutoTeleprompter stayed open so '
        'the current build was not lost.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  Future<void> _installMacOSUpdate(
    File packageFile,
    UpdateCheckResult result,
  ) async {
    if (!await packageFile.exists()) {
      throw StateError('Downloaded update package is missing.');
    }

    final currentApp = _currentMacAppBundle();
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

  Future<void> _extractPackage(File packageFile, Directory stageRoot) async {
    final archive = ZipDecoder().decodeBytes(await packageFile.readAsBytes());
    for (final entry in archive.files) {
      final relative = _safeArchivePath(entry.name);
      if (relative.isEmpty) continue;
      final targetPath = _joinPath(stageRoot.path, relative);
      if (entry.isFile) {
        final target = File(targetPath);
        await target.parent.create(recursive: true);
        await target.writeAsBytes(
          List<int>.from(entry.content as List),
          flush: true,
        );
      } else {
        await Directory(targetPath).create(recursive: true);
      }
    }
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

  Future<Directory> _findUpdateRoot(Directory stageRoot, String exeName) async {
    final rootExe = File(_joinPath(stageRoot.path, exeName));
    if (await rootExe.exists()) return stageRoot;

    await for (final entity in stageRoot.list(recursive: true)) {
      if (entity is File &&
          _baseName(entity.path).toLowerCase() == exeName.toLowerCase()) {
        return entity.parent;
      }
    }
    throw StateError('Update package does not contain $exeName.');
  }

  Future<_UpdateHandoff> _writeHandoffScript({
    required Directory updateRoot,
    required Directory installDir,
    required String exeName,
  }) async {
    final root = await _updatesDirectory();
    await root.create(recursive: true);
    final script = File(
      _joinPath(root.path, 'install_autoteleprompter_update.ps1'),
    );
    final log = File(
      _joinPath(root.path, 'install_autoteleprompter_update.log'),
    );
    final started = File(
      _joinPath(root.path, 'install_autoteleprompter_update.started'),
    );
    final success = File(
      _joinPath(root.path, 'install_autoteleprompter_update.success'),
    );
    final command = File(
      _joinPath(root.path, 'install_autoteleprompter_update.cmd'),
    );
    final launcher = File(
      _joinPath(root.path, 'install_autoteleprompter_update_launcher.vbs'),
    );
    final content = '''
\$ErrorActionPreference = 'Stop'
\$source = ${_psString(updateRoot.path)}
\$target = ${_psString(installDir.path)}
\$exeName = ${_psString(exeName)}
\$pidToWait = $pid
\$log = ${_psString(log.path)}
\$started = ${_psString(started.path)}
\$success = ${_psString(success.path)}
\$backupRoot = Join-Path (Join-Path \$target 'TMP') ${_psString(_updateTempFolderName)}
\$backup = \$null
\$scriptPath = \$PSCommandPath
\$commandPath = ${_psString(command.path)}
\$launcherPath = ${_psString(launcher.path)}
\$logDir = Split-Path -Parent \$log
New-Item -ItemType Directory -Force -Path \$logDir | Out-Null
Set-Content -LiteralPath \$started -Value (Get-Date).ToString("o") -Encoding UTF8

function Write-UpdateLog([string]\$message) {
  \$line = "[{0}] {1}" -f (Get-Date).ToString("s"), \$message
  Add-Content -LiteralPath \$log -Value \$line
}

try {
  Write-UpdateLog "Waiting for AutoTeleprompter process \$pidToWait to exit."
  try { Wait-Process -Id \$pidToWait -Timeout 60 -ErrorAction SilentlyContinue } catch {}
  try { Stop-Process -Id \$pidToWait -Force -ErrorAction SilentlyContinue } catch {}

  if (-not (Test-Path -LiteralPath \$source)) {
    throw "Staged update folder is missing: \$source"
  }
  if (-not (Test-Path -LiteralPath \$target)) {
    New-Item -ItemType Directory -Force -Path \$target | Out-Null
  }

  New-Item -ItemType Directory -Force -Path \$backupRoot | Out-Null
  \$backupStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
  \$backup = Join-Path \$backupRoot ("rollback_" + \$backupStamp)
  Write-UpdateLog "Backing up current runtime to \$backup."
  New-Item -ItemType Directory -Force -Path \$backup | Out-Null
  \$excludeDirs = @(
    (Join-Path \$target 'TMP'),
    (Join-Path \$target 'Scripts'),
    (Join-Path \$target 'Scripts Backup'),
    (Join-Path \$target 'debug_artifacts'),
    (Join-Path \$target 'feedback_outbox'),
    (Join-Path \$target 'local_backup_history'),
    (Join-Path \$target 'secure_storage')
  )
  & robocopy \$target \$backup /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP /XD \$excludeDirs
  \$backupCode = \$LASTEXITCODE
  if (\$backupCode -ge 8) {
    throw "Runtime backup failed with code \$backupCode."
  }

  Write-UpdateLog "Copying update from \$source to \$target."
  & robocopy \$source \$target /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP
  \$copyCode = \$LASTEXITCODE
  if (\$copyCode -ge 8) {
    throw "Robocopy failed with code \$copyCode."
  }

  \$exePath = Join-Path \$target \$exeName
  if (-not (Test-Path -LiteralPath \$exePath)) {
    throw "Updated executable is missing: \$exePath"
  }

  Write-UpdateLog "Relaunching AutoTeleprompter."
  Start-Process -FilePath \$exePath -WorkingDirectory \$target -WindowStyle Normal
  Set-Content -LiteralPath \$success -Value (Get-Date).ToString("o") -Encoding UTF8
  Start-Sleep -Seconds 2
  try { Remove-Item -LiteralPath \$scriptPath -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item -LiteralPath \$commandPath -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item -LiteralPath \$launcherPath -Force -ErrorAction SilentlyContinue } catch {}
} catch {
  Write-UpdateLog ("Update install failed: " + \$_.Exception.Message)
  if (\$backup -and (Test-Path -LiteralPath \$backup)) {
    Write-UpdateLog "Attempting rollback from \$backup."
    try {
      & robocopy \$backup \$target /E /COPY:DAT /DCOPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS /NP
      \$rollbackCode = \$LASTEXITCODE
      if (\$rollbackCode -ge 8) {
        Write-UpdateLog "Rollback robocopy failed with code \$rollbackCode."
      } else {
        \$oldExePath = Join-Path \$target \$exeName
        if (Test-Path -LiteralPath \$oldExePath) {
          Write-UpdateLog "Relaunching previous AutoTeleprompter runtime."
          Start-Process -FilePath \$oldExePath -WorkingDirectory \$target -WindowStyle Normal
        }
      }
    } catch {
      Write-UpdateLog ("Rollback failed: " + \$_.Exception.Message)
    }
  }
  try { Start-Process explorer.exe -ArgumentList \$backupRoot } catch {}
  exit 1
}
''';
    await script.writeAsString(content, flush: true);
    final launcherContent = '''
Dim shell
Dim command
Set shell = CreateObject("WScript.Shell")
command = Chr(34) & "${_vbsString(_powershellExecutable())}" & Chr(34) & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & "${_vbsString(script.path)}" & Chr(34)
shell.Run command, 0, False
''';
    await launcher.writeAsString(launcherContent, flush: true);
    final commandContent = '''
@echo off
start "" /b "${_cmdString(_wscriptExecutable())}" //B //Nologo "${_cmdString(launcher.path)}"
''';
    await command.writeAsString(commandContent, flush: true);
    return _UpdateHandoff(
      scriptFile: script,
      commandFile: command,
      launcherFile: launcher,
      logFile: log,
      startedFile: started,
      successFile: success,
    );
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
    rm -rf "\$new_app" >/dev/null 2>&1 || true
    if [ -n "\$backup_app" ] && [ -d "\$backup_app" ]; then
      log_msg "Attempting rollback from \$backup_app."
      rm -rf "\$target_app"
      /usr/bin/ditto "\$backup_app" "\$target_app" || true
      /usr/bin/open -n "\$target_app" || true
    fi
    /usr/bin/open -R "\$backup_root" || true
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
    );
  }

  Future<bool> _waitForInstallerStart(File startedFile) async {
    for (var i = 0; i < 25; i++) {
      if (await startedFile.exists()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _startInstallerHandoff(_UpdateHandoff handoff) async {
    await Process.start(
      _wscriptExecutable(),
      [
        '//B',
        '//Nologo',
        handoff.launcherFile.path,
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: handoff.launcherFile.parent.path,
    );
  }

  Future<void> _startInstallerHandoffViaCmd(_UpdateHandoff handoff) async {
    await Process.start(
      'cmd.exe',
      ['/d', '/c', handoff.commandFile.path],
      mode: ProcessStartMode.detached,
      workingDirectory: handoff.commandFile.parent.path,
    );
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
    final installDir = File(Platform.resolvedExecutable).parent;
    return Directory(
      _joinPath(_joinPath(installDir.path, 'TMP'), _updateTempFolderName),
    );
  }

  static String _safeArchivePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts =
        normalized.split('/').where((part) => part.trim().isNotEmpty).toList();
    if (parts.any(
      (part) => part == '.' || part == '..' || part.contains(':'),
    )) {
      throw FormatException('Update package contains an unsafe path: $name');
    }
    return parts.join(Platform.pathSeparator);
  }

  static String _safeName(String value) {
    return value
        .trim()
        .replaceAll('+', '-')
        .replaceAll(RegExp(r'[<>:"/\\|?*\s]+'), '_');
  }

  static String _psString(String value) => "'${value.replaceAll("'", "''")}'";

  static String _cmdString(String value) => value.replaceAll('"', r'\"');

  static String _vbsString(String value) => value.replaceAll('"', '""');

  static String _shString(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static String _powershellExecutable() {
    final systemRoot = Platform.environment['SystemRoot']?.trim();
    if (systemRoot != null && systemRoot.isNotEmpty) {
      return _joinPath(
        systemRoot,
        'System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      );
    }
    return 'powershell.exe';
  }

  static String _wscriptExecutable() {
    final systemRoot = Platform.environment['SystemRoot']?.trim();
    if (systemRoot != null && systemRoot.isNotEmpty) {
      return _joinPath(systemRoot, 'System32\\wscript.exe');
    }
    return 'wscript.exe';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  static String _joinPath(String left, String right) {
    if (left.endsWith(Platform.pathSeparator)) return '$left$right';
    return '$left${Platform.pathSeparator}$right';
  }
}

class _UpdateHandoff {
  final File scriptFile;
  final File commandFile;
  final File launcherFile;
  final File logFile;
  final File startedFile;
  final File successFile;

  const _UpdateHandoff({
    required this.scriptFile,
    required this.commandFile,
    required this.launcherFile,
    required this.logFile,
    required this.startedFile,
    required this.successFile,
  });
}

class _MacUpdateHandoff {
  final File scriptFile;
  final File logFile;
  final File startedFile;
  final File successFile;

  const _MacUpdateHandoff({
    required this.scriptFile,
    required this.logFile,
    required this.startedFile,
    required this.successFile,
  });
}
