[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $ReleaseRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AbsolutePath {
  param([Parameter(Mandatory = $true)][string] $Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine((Get-Location).Path, $Path)
  )
}

$releaseRootPath = Get-AbsolutePath -Path $ReleaseRoot
if (-not (Test-Path -LiteralPath $releaseRootPath -PathType Container)) {
  throw "Windows release root does not exist: $releaseRootPath"
}
$releasePrefix = $releaseRootPath.TrimEnd('\', '/') +
  [System.IO.Path]::DirectorySeparatorChar

$nativeExtensions = @(
  '.dll',
  '.exe',
  '.pyd',
  '.node',
  '.so',
  '.dylib',
  '.lib',
  '.a'
)
$violations = @(
  Get-ChildItem -LiteralPath $releaseRootPath -File -Recurse -Force |
    ForEach-Object {
      $lowerName = $_.Name.ToLowerInvariant()
      $lowerExtension = $_.Extension.ToLowerInvariant()
      $reason = $null

      if ($lowerName -eq 'whisper_ggml.dll') {
        $reason = 'Whisper native plugin'
      } elseif ($lowerName -eq 'record_windows_plugin.dll') {
        # V5 Build 63 uses browser STT only. The record plugin belongs to the
        # deferred native Whisper path and must not enter this release.
        $reason = 'deferred native recording plugin'
      } elseif ($lowerName.Contains('whisper') -and
          $nativeExtensions -contains $lowerExtension) {
        $reason = 'Whisper-named native binary'
      } elseif ($lowerName -match '^ggml(?:[-_.].*)?\.(?:bin|gguf)$') {
        $reason = 'GGML model asset'
      }

      if ($null -ne $reason) {
        $filePath = [System.IO.Path]::GetFullPath($_.FullName)
        if (-not $filePath.StartsWith(
            $releasePrefix,
            [System.StringComparison]::OrdinalIgnoreCase
          )) {
          throw 'Release artifact scan escaped the requested root.'
        }
        [PSCustomObject]@{
          Path = $filePath.Substring($releasePrefix.Length)
          Reason = $reason
        }
      }
    }
)

if ($violations.Count -gt 0) {
  $details = @(
    $violations |
      Sort-Object -Property Path |
      ForEach-Object { "  - $($_.Path) [$($_.Reason)]" }
  ) -join [System.Environment]::NewLine
  throw "V5 browser-only STT artifact guard failed:$([System.Environment]::NewLine)$details"
}

Write-Output 'V5 browser-only STT artifact guard passed.'
