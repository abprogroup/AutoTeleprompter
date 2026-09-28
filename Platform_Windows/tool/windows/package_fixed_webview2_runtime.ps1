[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $DestinationRoot,

  [Parameter(Mandatory = $false)]
  [string] $CabPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runtimeVersion = '152.0.4191.62'
$runtimeUri = 'https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/0a4a34d9-ccaa-4cef-98b4-58cb313fbfeb/Microsoft.WebView2.FixedVersionRuntime.152.0.4191.62.x64.cab'
$cabFileName = 'Microsoft.WebView2.FixedVersionRuntime.152.0.4191.62.x64.cab'
$expectedCabSize = [Int64] 371877369
$expectedCabSha256 = '2DC7D817DDCE4D036F33684425C218F1CA2D073911136E5D3F8CE9B2340569B5'
$expectedExeSize = [Int64] 4824392
$expectedExeSha256 = '0F75BA7DA899408D4C4474D58358BDBEE732705FC090161CBF08E8783520572D'
$expectedMachine = [UInt16] 0x8664

function Get-AbsolutePath {
  param([Parameter(Mandatory = $true)][string] $Path)

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }
  return [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine((Get-Location).Path, $Path)
  )
}

function Assert-LocalDestination {
  param([Parameter(Mandatory = $true)][string] $Path)

  if ($Path.StartsWith('\\', [System.StringComparison]::Ordinal)) {
    throw "Fixed WebView2 destination must not be a UNC path."
  }

  $root = [System.IO.Path]::GetPathRoot($Path)
  if ([string]::IsNullOrWhiteSpace($root) -or
      $root.StartsWith('\\', [System.StringComparison]::Ordinal)) {
    throw "Fixed WebView2 destination must be on a local Windows drive."
  }

  try {
    $drive = [System.IO.DriveInfo]::new($root)
    if ($drive.DriveType -eq [System.IO.DriveType]::Network) {
      throw "Fixed WebView2 destination must not be on a mapped network drive."
    }
  } catch [System.ArgumentException] {
    throw "Fixed WebView2 destination has an invalid drive root."
  }
}

function Test-PinnedCab {
  param([Parameter(Mandatory = $true)][string] $Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }

  $file = Get-Item -LiteralPath $Path
  if ($file.Length -ne $expectedCabSize) {
    return $false
  }

  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  return $hash.Equals($expectedCabSha256, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-X64PortableExecutable {
  param([Parameter(Mandatory = $true)][string] $Path)

  $stream = [System.IO.File]::Open(
    $Path,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::Read
  )
  try {
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
      if ($reader.ReadUInt16() -ne 0x5A4D) {
        throw "Fixed WebView2 executable has an invalid DOS header."
      }
      $stream.Position = 0x3C
      $peOffset = $reader.ReadInt32()
      if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
        throw "Fixed WebView2 executable has an invalid PE header offset."
      }
      $stream.Position = $peOffset
      if ($reader.ReadUInt32() -ne 0x00004550) {
        throw "Fixed WebView2 executable has an invalid PE signature."
      }
      $machine = $reader.ReadUInt16()
      if ($machine -ne $expectedMachine) {
        throw ('Fixed WebView2 executable architecture mismatch: expected x64 ' +
          "(0x{0:X4}), found 0x{1:X4}." -f $expectedMachine, $machine)
      }
    } finally {
      $reader.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Assert-PinnedRuntimeExecutable {
  param([Parameter(Mandatory = $true)][string] $Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Expanded Fixed WebView2 runtime is missing msedgewebview2.exe."
  }

  $file = Get-Item -LiteralPath $Path
  if ($file.Length -ne $expectedExeSize) {
    throw "Fixed WebView2 executable size verification failed."
  }

  $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if (-not $hash.Equals($expectedExeSha256, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Fixed WebView2 executable checksum verification failed."
  }

  $fileVersion = ([string] $file.VersionInfo.FileVersion).Trim()
  $productVersion = ([string] $file.VersionInfo.ProductVersion).Trim()
  if ($fileVersion -ne $runtimeVersion -or $productVersion -ne $runtimeVersion) {
    throw "Fixed WebView2 executable version verification failed."
  }

  Assert-X64PortableExecutable -Path $Path

  $signature = Get-AuthenticodeSignature -LiteralPath $Path
  if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
      $null -eq $signature.SignerCertificate -or
      $signature.SignerCertificate.Subject -notmatch '(?i)(^|,\s*)O=Microsoft Corporation(,|$)') {
    throw "Fixed WebView2 executable does not have a valid Microsoft Authenticode signature."
  }
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
  throw "Fixed WebView2 runtime packaging requires Windows."
}

$destinationRootPath = Get-AbsolutePath -Path $DestinationRoot
Assert-LocalDestination -Path $destinationRootPath

if ([string]::IsNullOrWhiteSpace($CabPath)) {
  $platformRoot = Get-AbsolutePath -Path (Join-Path $PSScriptRoot '..\..')
  $CabPath = Join-Path $platformRoot "build\cache\webview2\$cabFileName"
}
$cabFullPath = Get-AbsolutePath -Path $CabPath

$cabDirectory = Split-Path -Parent $cabFullPath
New-Item -ItemType Directory -Path $cabDirectory -Force | Out-Null

if (Test-Path -LiteralPath $cabFullPath -PathType Leaf) {
  if (-not (Test-PinnedCab -Path $cabFullPath)) {
    throw "Existing Fixed WebView2 CAB failed pinned size or checksum validation: $cabFullPath"
  }
  Write-Output "Using verified cached Fixed WebView2 CAB."
} else {
  $partialCabPath = "$cabFullPath.$([Guid]::NewGuid().ToString('N')).part"
  try {
    $curl = Get-Command curl.exe -ErrorAction Stop
    & $curl.Source --fail --location --retry 3 --retry-delay 2 --output $partialCabPath $runtimeUri
    if ($LASTEXITCODE -ne 0) {
      throw "Fixed WebView2 CAB download failed."
    }
    if (-not (Test-PinnedCab -Path $partialCabPath)) {
      throw "Downloaded Fixed WebView2 CAB failed pinned size or checksum validation."
    }
    Move-Item -LiteralPath $partialCabPath -Destination $cabFullPath
    Write-Output "Downloaded and verified pinned Fixed WebView2 CAB."
  } finally {
    if (Test-Path -LiteralPath $partialCabPath) {
      Remove-Item -LiteralPath $partialCabPath -Force
    }
  }
}

$runtimeParent = Join-Path $destinationRootPath 'runtime\webview2'
$runtimeTarget = Join-Path $runtimeParent $runtimeVersion
$runtimeTargetPath = Get-AbsolutePath -Path $runtimeTarget
$destinationPrefix = $destinationRootPath.TrimEnd('\') + '\'
if (-not $runtimeTargetPath.StartsWith(
    $destinationPrefix,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
  throw "Fixed WebView2 runtime target escaped the requested destination root."
}

New-Item -ItemType Directory -Path $runtimeParent -Force | Out-Null
$stagingPath = Join-Path $runtimeParent ("$runtimeVersion.staging-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagingPath | Out-Null

try {
  $expand = Get-Command expand.exe -ErrorAction Stop
  & $expand.Source '-F:*' $cabFullPath $stagingPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Fixed WebView2 CAB expansion failed."
  }

  $runtimeExecutables = @(
    Get-ChildItem -LiteralPath $stagingPath -Filter 'msedgewebview2.exe' -File -Recurse
  )
  if ($runtimeExecutables.Count -ne 1) {
    throw "Expanded Fixed WebView2 CAB must contain exactly one msedgewebview2.exe."
  }

  $expandedRuntimeRoot = $runtimeExecutables[0].Directory.FullName
  Assert-PinnedRuntimeExecutable -Path $runtimeExecutables[0].FullName

  if (Test-Path -LiteralPath $runtimeTargetPath) {
    $existingTarget = Get-Item -LiteralPath $runtimeTargetPath -Force
    if (($existingTarget.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Refusing to replace a Fixed WebView2 runtime reparse point."
    }
    $existingTargetPath = [System.IO.Path]::GetFullPath($existingTarget.FullName)
    if (-not $existingTargetPath.StartsWith(
        $destinationPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
      )) {
      throw "Existing Fixed WebView2 runtime escaped the requested destination root."
    }
    Remove-Item -LiteralPath $runtimeTargetPath -Recurse -Force
  }
  Move-Item -LiteralPath $expandedRuntimeRoot -Destination $runtimeTargetPath

  $packagedExecutable = Join-Path $runtimeTargetPath 'msedgewebview2.exe'
  Assert-PinnedRuntimeExecutable -Path $packagedExecutable
  Write-Output "Packaged verified Fixed WebView2 x64 runtime $runtimeVersion."
} finally {
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
  }
}
