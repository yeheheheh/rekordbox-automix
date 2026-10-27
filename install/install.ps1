[CmdletBinding()]
param(
    [string]$InstallDir = "",
    [string]$TorchIndexUrl = "https://download.pytorch.org/whl/cu128",
    [string]$TorchWheel = "",
    [string]$TorchaudioWheel = "",
    [switch]$Cpu,
    [switch]$SkipRubberband,
    [switch]$NoShortcut,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $InstallDir) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path $env:USERPROFILE "AppData\Local" }
    $InstallDir = Join-Path $base "djcore"
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$Root = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $InstallDir "app"
$VenvDir = Join-Path $InstallDir "venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$LogPath = Join-Path $InstallDir "install.log"
$Transcript = $false

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-Python {
    $candidates = @()
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        try {
            $path = & py -3.12 -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $path) { $candidates += $path.Trim() }
        } catch { }
    }
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        try {
            $path = & python -c "import sys; print(sys.executable)" 2>$null
            if ($LASTEXITCODE -eq 0 -and $path) { $candidates += $path.Trim() }
        } catch { }
    }
    $localPython = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (Test-Path $localPython) {
        $candidates += Get-ChildItem $localPython -Directory -Filter "Python312*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "python.exe" }
    }
    $candidates += @("C:\Python312\python.exe")
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate -or -not (Test-Path $candidate)) { continue }
        try {
            $version = & $candidate -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $version -and $version.Trim() -eq "3.12") {
                return $candidate
            }
        } catch { }
    }
    return $null
}

function Install-Python {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Python 3.12 was not found. Install it from https://www.python.org/downloads/ and run install.bat again."
    }
    Write-Step "Python 3.12 not found; installing via winget"
    & winget install --id Python.Python.3.12 -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
    $found = Find-Python
    if (-not $found) {
        throw "winget finished but Python 3.12 is still not visible. Open a new terminal and run install.bat again."
    }
    return $found
}

function Invoke-Pip([string[]]$Arguments) {
    if ($script:UseUv) {
        & uv pip install --python $VenvPython @Arguments
    } else {
        & $VenvPython -m pip install @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "package install failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

$python = Find-Python
$UseUv = [bool](Get-Command uv -ErrorAction SilentlyContinue)
$hasNvidia = ($null -ne (Get-Command nvidia-smi -ErrorAction SilentlyContinue))
$dbCandidates = @(
    (Join-Path $env:APPDATA "Pioneer\rekordbox\master.db"),
    (Join-Path $env:APPDATA "Pioneer\rekordbox6\master.db")
)
$rekordboxDb = $dbCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$useCpu = $Cpu -or (-not $hasNvidia)
$torchMode = if ($TorchWheel) { "local wheel" } elseif ($useCpu) { "cpu" } else { $TorchIndexUrl }

if ($DryRun) {
    Write-Host "rekordbox-automix installer (dry run)"
    Write-Host "  source:        $Root"
    Write-Host "  install dir:   $InstallDir"
    Write-Host "  app dir:       $AppDir"
    Write-Host "  python:        $(if ($python) { $python } else { 'not found (would use winget)' })"
    Write-Host "  installer:     $(if ($UseUv) { 'uv pip (fast)' } else { 'pip (fallback)' })"
    Write-Host "  nvidia-smi:    $hasNvidia"
    Write-Host "  torch mode:    $torchMode"
    Write-Host "  rekordbox db:  $(if ($rekordboxDb) { $rekordboxDb } else { 'not found (you can set DJ_REKORDBOX_DB later)' })"
    Write-Host "  rubberband:    $(if ($SkipRubberband) { 'skipped' } else { 'download portable build' })"
    Write-Host "  shortcuts:     $(if ($NoShortcut) { 'skipped' } else { 'desktop + start menu' })"
    exit 0
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}
try {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $Transcript = $true
} catch { }

$exitCode = 0
try {
    Write-Step "Installing rekordbox-automix to $InstallDir"

    if (-not $python) { $python = Install-Python }
    Write-Host "Python 3.12: $python"
    Write-Host "Package manager: $(if ($UseUv) { 'uv' } else { 'pip' })"

    if ((Test-Path $AppDir) -and ((Resolve-Path $AppDir).Path -eq (Resolve-Path $Root).Path)) {
        Write-Host "Running from the installed app; skipping file copy."
    } else {
        Write-Step "Copying application files"
        New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
        $robocopyArgs = @(
            $Root, $AppDir, "/E",
            "/XD", ".git", ".venv", "tools", "outputs", "fixtures\audio", "__pycache__", ".pytest_cache",
            "/XF", "*.pyc", "install.log",
            "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
        )
        & robocopy @robocopyArgs | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed with exit code $LASTEXITCODE"
        }
    }

    Write-Step "Creating virtual environment"
    if (-not (Test-Path $VenvPython)) {
        & $python -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) { throw "python -m venv failed" }
    }
    if (-not $UseUv) {
        Invoke-Pip @("--upgrade", "pip", "setuptools", "wheel")
    }

    Write-Step "Installing PyTorch ($torchMode)"
    if ($TorchWheel) {
        if (-not (Test-Path $TorchWheel)) { throw "TorchWheel not found: $TorchWheel" }
        if (-not $TorchaudioWheel -or -not (Test-Path $TorchaudioWheel)) {
            throw "TorchWheel also requires -TorchaudioWheel (matching cu build)."
        }
        Invoke-Pip @("--force-reinstall", $TorchWheel, $TorchaudioWheel)
    } elseif ($useCpu) {
        Invoke-Pip @("torch", "torchaudio", "--index-url", "https://download.pytorch.org/whl/cpu")
    } else {
        Invoke-Pip @("torch", "torchaudio", "--index-url", $TorchIndexUrl)
    }

    Write-Step "Installing application dependencies"
    Invoke-Pip @("-e", $AppDir)

    if (-not $SkipRubberband) {
        Write-Step "Installing portable rubberband (optional)"
        $toolsDir = Join-Path $AppDir "tools"
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        $zip = Join-Path $toolsDir "rubberband.zip"
        try {
            Invoke-WebRequest -Uri "https://breakfastquay.com/files/releases/rubberband-3.3.0-gpl-executable-windows.zip" -OutFile $zip -UseBasicParsing
            $extract = Join-Path $toolsDir "rubberband-extract"
            if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
            Expand-Archive -Path $zip -DestinationPath $extract -Force
            $exe = Get-ChildItem -Path $extract -Recurse -Filter "rubberband.exe" | Select-Object -First 1
            if ($exe) {
                $dest = Join-Path $toolsDir "rubberband"
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
                Copy-Item (Join-Path $exe.DirectoryName "*") $dest -Recurse -Force
                Write-Host "rubberband installed to $dest"
            } else {
                Write-Warning "rubberband.exe not found in the archive; librosa fallback will be used."
            }
        } catch {
            Write-Warning "rubberband install failed; librosa fallback will be used. $_"
        }
    }

    Write-Step "Writing configuration and launchers"
    $config = [ordered]@{
        installDir = $InstallDir
        appDir = $AppDir
        venv = $VenvDir
        rekordboxDb = $rekordboxDb
        apiPort = 5601
        installedAt = (Get-Date).ToString("o")
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $InstallDir "config.json"), ($config | ConvertTo-Json -Depth 5), $utf8)

    $startApi = @"
@echo off
cd /d "%~dp0app"
"%~dp0venv\Scripts\python.exe" -m djcore.adapters.api
pause
"@
    $statusBat = @"
@echo off
cd /d "%~dp0app"
"%~dp0venv\Scripts\python.exe" -m djcore.adapters.cli rekordbox status
pause
"@
    $demoBat = @"
@echo off
cd /d "%~dp0app"
"%~dp0venv\Scripts\python.exe" -m djcore.adapters.cli run --preset melodic-techno --duration 4
pause
"@
    $uninstallBat = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\install\uninstall.ps1" -InstallDir "%~dp0"
pause
"@
    Set-Content -Path (Join-Path $InstallDir "start-api.bat") -Value $startApi -Encoding ASCII
    Set-Content -Path (Join-Path $InstallDir "rekordbox-status.bat") -Value $statusBat -Encoding ASCII
    Set-Content -Path (Join-Path $InstallDir "local-demo.bat") -Value $demoBat -Encoding ASCII
    Set-Content -Path (Join-Path $InstallDir "uninstall.bat") -Value $uninstallBat -Encoding ASCII

    $mcp = [ordered]@{
        mcpServers = [ordered]@{
            djcore = [ordered]@{
                command = $VenvPython
                args = @("-m", "djcore.adapters.mcp_server")
                env = [ordered]@{ PYTHONPATH = $AppDir }
            }
        }
    }
    [IO.File]::WriteAllText((Join-Path $InstallDir "mcp-config.json"), ($mcp | ConvertTo-Json -Depth 6), $utf8)

    if (-not $NoShortcut) {
        Write-Step "Creating shortcuts"
        try {
            $shell = New-Object -ComObject WScript.Shell
            $desktop = [Environment]::GetFolderPath("Desktop")
            $shortcut = $shell.CreateShortcut((Join-Path $desktop "djcore API.lnk"))
            $shortcut.TargetPath = Join-Path $InstallDir "start-api.bat"
            $shortcut.WorkingDirectory = $InstallDir
            $shortcut.Description = "djcore local API (Rekordbox automix)"
            $shortcut.Save()

            $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\djcore"
            New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
            foreach ($item in @(
                @("djcore API", "start-api.bat"),
                @("Rekordbox status", "rekordbox-status.bat"),
                @("Uninstall djcore", "uninstall.bat")
            )) {
                $link = $shell.CreateShortcut((Join-Path $startMenu ($item[0] + ".lnk")))
                $link.TargetPath = Join-Path $InstallDir $item[1]
                $link.WorkingDirectory = $InstallDir
                $link.Save()
            }
        } catch {
            Write-Warning "Shortcut creation failed: $_"
        }
    }

    Write-Step "Done"
    Write-Host "Install dir:   $InstallDir"
    Write-Host "Python:        $python"
    Write-Host "Torch mode:    $torchMode"
    Write-Host "Installer:     $(if ($UseUv) { 'uv' } else { 'pip' })"
    Write-Host "Rekordbox DB:  $(if ($rekordboxDb) { $rekordboxDb } else { 'not found' })"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Start the API: $InstallDir\start-api.bat"
    Write-Host "  2. Check Rekordbox: $InstallDir\rekordbox-status.bat"
    Write-Host "  3. Optional site console: http://127.0.0.1:5501/#/dj/automix"
    Write-Host "  4. MCP config: $InstallDir\mcp-config.json"
    Write-Host ""
    Write-Host "Writing a Rekordbox playlist requires Rekordbox to be closed; the app backs up master.db first."
} catch {
    $exitCode = 1
    Write-Host ""
    Write-Host "INSTALL FAILED: $_" -ForegroundColor Red
    Write-Host "Log: $LogPath"
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace }
} finally {
    if ($Transcript) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
exit $exitCode
