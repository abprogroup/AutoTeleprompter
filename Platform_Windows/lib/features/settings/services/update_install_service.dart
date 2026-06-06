import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'update_check_service.dart';

class UpdateInstallService {
  Future<void> installDownloadedUpdate(
    File packageFile,
    UpdateCheckResult result,
  ) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
          'Automatic update install is only wired on Windows.');
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

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        handoff.path,
      ],
      mode: ProcessStartMode.detached,
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    exit(0);
  }

  Future<Directory> _createStageDirectory(UpdateCheckResult result) async {
    final root = await _updatesDirectory();
    await root.create(recursive: true);
    final version = _safeName(result.latestVersion ?? 'update');
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
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

  Future<File> _writeHandoffScript({
    required Directory updateRoot,
    required Directory installDir,
    required String exeName,
  }) async {
    final root = await _updatesDirectory();
    await root.create(recursive: true);
    final script =
        File(_joinPath(root.path, 'install_autoteleprompter_update.ps1'));
    final log =
        File(_joinPath(root.path, 'install_autoteleprompter_update.log'));
    final content = '''
\$ErrorActionPreference = 'Stop'
\$source = ${_psString(updateRoot.path)}
\$target = ${_psString(installDir.path)}
\$exeName = ${_psString(exeName)}
\$pidToWait = $pid
\$log = ${_psString(log.path)}
\$scriptPath = \$PSCommandPath

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
  Start-Sleep -Seconds 2
  try { Remove-Item -LiteralPath \$source -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  try { Remove-Item -LiteralPath \$scriptPath -Force -ErrorAction SilentlyContinue } catch {}
} catch {
  Write-UpdateLog ("Update install failed: " + \$_.Exception.Message)
  try { Start-Process explorer.exe -ArgumentList \$source } catch {}
  exit 1
}
''';
    await script.writeAsString(content, flush: true);
    return script;
  }

  static Future<Directory> _updatesDirectory() async {
    final downloads = await getDownloadsDirectory();
    final root = downloads ?? await getApplicationSupportDirectory();
    return Directory(_joinPath(root.path, 'AutoTeleprompter Updates'));
  }

  static String _safeArchivePath(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts =
        normalized.split('/').where((part) => part.trim().isNotEmpty).toList();
    if (parts
        .any((part) => part == '.' || part == '..' || part.contains(':'))) {
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
