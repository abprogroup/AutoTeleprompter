[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$guardPath = Join-Path $PSScriptRoot 'assert_v5_release_stt_artifacts.ps1'
$temporaryRoot = [System.IO.Path]::GetFullPath(
  [System.IO.Path]::Combine(
    [System.IO.Path]::GetTempPath(),
    "autoteleprompter-v5-artifact-guard-$([Guid]::NewGuid().ToString('N'))"
  )
)
$systemTemporaryRoot = [System.IO.Path]::GetFullPath(
  [System.IO.Path]::GetTempPath()
).TrimEnd('\') + '\'
if (-not $temporaryRoot.StartsWith(
    $systemTemporaryRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw 'Release guard test root escaped the system temporary directory.'
}

function New-GuardCase {
  param([Parameter(Mandatory = $true)][string] $Name)

  $casePath = Join-Path $temporaryRoot $Name
  New-Item -ItemType Directory -Path $casePath -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $casePath 'autoteleprompter.exe') -Value 'fixture'
  return $casePath
}

function Assert-GuardPasses {
  param([Parameter(Mandatory = $true)][string] $CasePath)

  & $guardPath -ReleaseRoot $CasePath | Out-Null
}

function Assert-GuardRejects {
  param(
    [Parameter(Mandatory = $true)][string] $CasePath,
    [Parameter(Mandatory = $true)][string] $ExpectedName
  )

  try {
    & $guardPath -ReleaseRoot $CasePath | Out-Null
  } catch {
    if ($_.Exception.Message -notmatch [Regex]::Escape($ExpectedName)) {
      throw "Guard rejected the fixture without naming '$ExpectedName'."
    }
    return
  }
  throw "Guard accepted forbidden release artifact '$ExpectedName'."
}

try {
  New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

  $clean = New-GuardCase -Name 'clean'
  New-Item -ItemType Directory -Path (Join-Path $clean 'notes') | Out-Null
  Set-Content -LiteralPath (Join-Path $clean 'notes\whisper-plan.txt') -Value 'future work'
  Set-Content -LiteralPath (Join-Path $clean 'not-ggml.bin') -Value 'unrelated'
  Assert-GuardPasses -CasePath $clean

  $whisperPlugin = New-GuardCase -Name 'whisper-plugin'
  Set-Content -LiteralPath (Join-Path $whisperPlugin 'whisper_ggml.dll') -Value 'fixture'
  Assert-GuardRejects -CasePath $whisperPlugin -ExpectedName 'whisper_ggml.dll'

  $recordPlugin = New-GuardCase -Name 'record-plugin'
  Set-Content -LiteralPath (Join-Path $recordPlugin 'record_windows_plugin.dll') -Value 'fixture'
  Assert-GuardRejects -CasePath $recordPlugin -ExpectedName 'record_windows_plugin.dll'

  $namedNative = New-GuardCase -Name 'named-native'
  Set-Content -LiteralPath (Join-Path $namedNative 'AutoWhisperEngine.exe') -Value 'fixture'
  Assert-GuardRejects -CasePath $namedNative -ExpectedName 'AutoWhisperEngine.exe'

  $modelAsset = New-GuardCase -Name 'model-asset'
  $modelDirectory = Join-Path $modelAsset 'data\flutter_assets\assets\models'
  New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $modelDirectory 'ggml-base.bin') -Value 'fixture'
  Assert-GuardRejects -CasePath $modelAsset -ExpectedName 'ggml-base.bin'

  Write-Output 'V5 release STT artifact guard tests passed.'
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}
