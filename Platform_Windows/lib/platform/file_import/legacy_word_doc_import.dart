import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Extracts visible text from legacy OLE/Word `.doc` files on Windows.
///
/// The binary Word format is not plain text. Windows imports use the locally
/// installed Microsoft Word converter with macros force-disabled and the
/// document opened read-only. The original document is never modified.
class LegacyWordDocImport {
  const LegacyWordDocImport._();

  static const _oleSignature = <int>[
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
  ];

  static const _timeout = Duration(seconds: 30);

  static bool hasOleSignature(List<int> bytes) {
    if (bytes.length < _oleSignature.length) return false;
    for (var index = 0; index < _oleSignature.length; index++) {
      if (bytes[index] != _oleSignature[index]) return false;
    }
    return true;
  }

  static Future<String> extractText(File input) async {
    if (!Platform.isWindows) {
      throw const LegacyWordDocImportException(
        'Legacy DOC import requires Microsoft Word on Windows. '
        'Please save the document as DOCX and try again.',
      );
    }

    final controlDirectory = await Directory.systemTemp.createTemp(
      'autoteleprompter_doc_import_',
    );
    final wordPidFile = File(
      '${controlDirectory.path}${Platform.pathSeparator}word.pid',
    );
    Process? process;
    try {
      final encodedScript = base64.encode(
        _utf16LeBytes(_powerShellExtractionScript),
      );
      process = await Process.start(
        'powershell.exe',
        <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-EncodedCommand',
          encodedScript,
        ],
        environment: <String, String>{
          'AUTOTELEPROMPTER_DOC_INPUT': input.absolute.path,
          'AUTOTELEPROMPTER_WORD_PID_FILE': wordPidFile.path,
        },
      );

      final stdoutFuture = process.stdout.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      final stderrFuture = process.stderr.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      late final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(_timeout);
      } on TimeoutException {
        process.kill();
        await _terminateOwnedWord(wordPidFile);
        throw const LegacyWordDocImportException(
          'Microsoft Word took too long to read this DOC file. '
          'Please save it as DOCX and try again.',
        );
      }

      final stdoutBytes = await stdoutFuture;
      final stderrText = utf8.decode(
        await stderrFuture,
        allowMalformed: true,
      );
      if (exitCode != 0 || stdoutBytes.isEmpty) {
        await _terminateOwnedWord(wordPidFile);
        throw LegacyWordDocImportException(
          _friendlyFailure(stderrText),
        );
      }
      try {
        final encodedText = utf8.decode(stdoutBytes, allowMalformed: true);
        final extractedText = utf8.decode(base64.decode(encodedText));
        return extractedText
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .replaceAll('\u000b', '\n')
            .replaceAll('\u0007', '')
            .trim();
      } on FormatException {
        throw const LegacyWordDocImportException(
          'Microsoft Word returned unreadable text for this DOC file. '
          'Please save it as DOCX and try again.',
        );
      }
    } on LegacyWordDocImportException {
      rethrow;
    } on ProcessException {
      throw const LegacyWordDocImportException(
        'Microsoft Word could not be started to read this DOC file. '
        'Please save it as DOCX and try again.',
      );
    } finally {
      process?.kill();
      try {
        if (await controlDirectory.exists()) {
          await controlDirectory.delete(recursive: true);
        }
      } on FileSystemException {
        // Best-effort cleanup; this directory contains only the Word PID.
      }
    }
  }

  static Future<void> _terminateOwnedWord(File wordPidFile) async {
    try {
      if (!await wordPidFile.exists()) return;
      final pid = int.tryParse((await wordPidFile.readAsString()).trim());
      if (pid == null || pid <= 0) return;
      final task = await Process.run(
        'tasklist.exe',
        <String>['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH'],
      );
      final processList = task.stdout.toString().toUpperCase();
      if (processList.contains('"WINWORD.EXE"')) Process.killPid(pid);
    } on FileSystemException {
      // The owning PowerShell process may have exited before writing its PID.
    }
  }

  static String _friendlyFailure(String stderrText) {
    final normalized = stderrText.toLowerCase();
    if (normalized.contains('class not registered') ||
        normalized.contains('invalid class string') ||
        normalized.contains('word.application')) {
      return 'Microsoft Word is required to read legacy DOC files. '
          'Please save the document as DOCX and try again.';
    }
    return 'This legacy DOC file could not be read safely. '
        'Please open it in Microsoft Word, save it as DOCX, and try again.';
  }

  static List<int> _utf16LeBytes(String value) => value.codeUnits
      .expand((unit) => <int>[unit & 0xFF, (unit >> 8) & 0xFF])
      .toList(growable: false);

  static const _powerShellExtractionScript = r'''
$ErrorActionPreference = 'Stop'
$word = $null
$document = $null
$bootstrapDocument = $null
try {
  [void](Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AutoTeleprompterNativeMethods {
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(
    IntPtr windowHandle,
    out uint processId
  );
}
'@)
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $word.DisplayAlerts = 0
  $word.AutomationSecurity = 3
  $bootstrapDocument = $word.Documents.Add()
  [uint32]$wordPid = 0
  [void][AutoTeleprompterNativeMethods]::GetWindowThreadProcessId(
    [IntPtr]$word.ActiveWindow.Hwnd,
    [ref]$wordPid
  )
  if ($wordPid -le 0) {
    throw 'Could not resolve the Word process used for this import.'
  }
  [System.IO.File]::WriteAllText(
    $env:AUTOTELEPROMPTER_WORD_PID_FILE,
    $wordPid.ToString(),
    [System.Text.Encoding]::ASCII
  )
  try {
    $bootstrapDocument.Close([ref]$false)
  } finally {
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject(
      $bootstrapDocument
    )
    $bootstrapDocument = $null
  }
  $document = $word.Documents.Open(
    $env:AUTOTELEPROMPTER_DOC_INPUT,
    $false,
    $true,
    $false
  )
  [Console]::Out.Write(
    [Convert]::ToBase64String(
      [System.Text.Encoding]::UTF8.GetBytes($document.Content.Text)
    )
  )
} finally {
  try {
    try {
      if ($null -ne $document) {
        try {
          $document.Close([ref]$false)
        } finally {
          [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject(
            $document
          )
        }
      }
    } finally {
      if ($null -ne $bootstrapDocument) {
        try {
          $bootstrapDocument.Close([ref]$false)
        } finally {
          [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject(
            $bootstrapDocument
          )
        }
      }
    }
  } finally {
    if ($null -ne $word) {
      try {
        $word.Quit()
      } finally {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($word)
      }
    }
  }
}
''';
}

class LegacyWordDocImportException implements Exception {
  final String message;

  const LegacyWordDocImportException(this.message);

  @override
  String toString() => message;
}
