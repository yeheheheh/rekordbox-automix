[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
if (-not $InstallDir) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE "AppData\Local" }
    $InstallDir = Join-Path $base "djcore"
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir.TrimEnd('\'))

if (-not $Force) {
    Write-Host "This will remove:"
    Write-Host "  $InstallDir"
    Write-Host "including the venv and all rendered outputs."
    $answer = Read-Host "Continue? (y/N)"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Cancelled."
        exit 0
    }
    $temp = Join-Path $env:TEMP ("djcore-uninstall-" + [guid]::NewGuid().ToString("N") + ".ps1")
    Copy-Item $PSCommandPath $temp -Force
    $arguments = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $temp, "-InstallDir", $InstallDir, "-Force"
    )
    Start-Process powershell -ArgumentList $arguments -Wait
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
    exit 0
}

Write-Host "Removing shortcuts..."
$desktop = [Environment]::GetFolderPath("Desktop")
Remove-Item (Join-Path $desktop "djcore API.lnk") -Force -ErrorAction SilentlyContinue
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\djcore"
if (Test-Path $startMenu) {
    Remove-Item $startMenu -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $InstallDir) {
    Write-Host "Removing $InstallDir ..."
    try {
        Remove-Item $InstallDir -Recurse -Force -ErrorAction Stop
        Write-Host "Removed."
    } catch {
        Write-Host "Could not remove everything (is the djcore API still running?)." -ForegroundColor Yellow
        Write-Host "$_"
        Write-Host "Close djcore/terminal windows and run uninstall.bat again."
        exit 1
    }
} else {
    Write-Host "Nothing to remove."
}
