import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';

import 'update_check_service.dart';

class UpdateInstallService {
  static const _updateTempFolderName = 'AutoTeleprompter Updates';

  static Future<void> cleanupCompletedUpdateTemp() async {
    if (!Platform.isWindows) return;
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
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Automatic update install is only wired on Windows.',
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
    final content =
        '''
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
  Start-Process -FilePath \$exePath -WorkingDirectory \$target
  Set-Content -LiteralPath \$success -Value (Get-Date).ToString("o") -Encoding UTF8
  Start-Sleep -Seconds 2
  try { Remove-Item -LiteralPath \$scriptPath -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item -LiteralPath \$commandPath -Force -ErrorAction SilentlyContinue } catch {}
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
          Start-Process -FilePath \$oldExePath -WorkingDirectory \$target
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
    final commandContent =
        '''
@echo off
start "" /min "${_cmdString(_powershellExecutable())}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${_cmdString(script.path)}"
''';
    await command.writeAsString(commandContent, flush: true);
    return _UpdateHandoff(
      scriptFile: script,
      commandFile: command,
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
      _powershellExecutable(),
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        handoff.scriptFile.path,
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: handoff.scriptFile.parent.path,
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

  static Future<Directory> _updatesDirectory() async {
    final installDir = File(Platform.resolvedExecutable).parent;
    return Directory(
      _joinPath(_joinPath(installDir.path, 'TMP'), _updateTempFolderName),
    );
  }

  static String _safeArchivePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();
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
  final File logFile;
  final File startedFile;
  final File successFile;

  const _UpdateHandoff({
    required this.scriptFile,
    required this.commandFile,
    required this.logFile,
    required this.startedFile,
    required this.successFile,
  });
}
