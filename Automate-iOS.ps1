# Automate-iOS.ps1
# This script monitors the GitHub Actions for AutoTeleprompter and downloads the iOS IPA to the Desktop.

$repo = "abprogroup/AutoTeleprompter"
$artifactName = "AutoTeleprompter-iOS"
$desktop = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop")
$targetFolder = [System.IO.Path]::Combine($desktop, "AutoTeleprompter_iPhone")
$ghPath = "C:\Program Files\GitHub CLI\gh.exe"

# If the standard gh command is not in the path, use the absolute path we found
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    function gh { & $ghPath $args }
}

Write-Host "[INFO] Starting Auto-Download for AutoTeleprompter iOS..." -ForegroundColor Cyan

# 1. Check Login
$authStatus = gh auth status 2>&1
if ($authStatus -match "Logged in to github.com") {
    Write-Host "[SUCCESS] Logged into GitHub." -ForegroundColor Green
} else {
    Write-Host "[ERROR] You are not logged into GitHub CLI yet." -ForegroundColor Red
    Write-Host "Please run: gh auth login" -ForegroundColor Yellow
    exit 1
}

# 2. Wait for the Run
Write-Host "[SEARCH] Searching for the latest Build..." -ForegroundColor Yellow
$run = gh run list --workflow "build-ios.yml" --limit 1 --json databaseId,status,conclusion | ConvertFrom-Json

if (-not $run) {
    Write-Host "[ERROR] Could not find any iOS build runs on GitHub." -ForegroundColor Red
    exit 1
}

$runId = $run[0].databaseId
$status = $run[0].status

# 3. Wait if Running
while ($status -ne "completed") {
    Write-Host "[WAIT] Build #$runId is still $status... (Waiting 30 seconds)" -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    $runRaw = gh run view $runId --json status,conclusion
    $runDetail = $runRaw | ConvertFrom-Json
    $status = $runDetail.status
}

if ($runDetail.conclusion -ne "success") {
    Write-Host "[ERROR] Build failed on GitHub. Opening logs..." -ForegroundColor Red
    Start-Process "https://github.com/$repo/actions/runs/$runId"
    exit 1
}

# 4. Download
Write-Host "[DOWNLOAD] Build Finished! Downloading Artifact..." -ForegroundColor Green
if (Test-Path $targetFolder) { Remove-Item -Recurse -Force $targetFolder }
mkdir $targetFolder | Out-Null

gh run download $runId --name $artifactName --dir $targetFolder

# 5. Open and Instructions
Write-Host "[OPEN] Opening Folder..." -ForegroundColor Cyan
Start-Process $targetFolder

# Try to launch Sideloadly if shortcut exists
$sideloadlyLnk = [System.IO.Path]::Combine($desktop, "Sideloadly.lnk")
if (Test-Path $sideloadlyLnk) {
    Write-Host "[LAUNCH] Launching Sideloadly..." -ForegroundColor Cyan
    Start-Process $sideloadlyLnk
}

Write-Host "--------------------------------------------------------"
Write-Host "DONE! Your iPhone App is now in front of you." -ForegroundColor Green
Write-Host "1. Drag the .ipa file into Sideloadly."
Write-Host "2. Click Start!"
Write-Host "--------------------------------------------------------"
