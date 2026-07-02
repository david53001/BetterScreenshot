<#
.SYNOPSIS
    Builds BetterScreenshot into a runnable, self-contained Windows app.

.DESCRIPTION
    Publishes BetterScreenshot.App as a self-contained win-x64 folder (no .NET install required
    on the target machine) into  windows/dist/BetterScreenshot/  and, by default, drops a
    double-clickable shortcut on the Desktop.

    This is the Windows analogue of the macOS app's scripts/build-app.sh.

.PARAMETER Runtime
    RID to publish for. Default: win-x64.

.PARAMETER NoShortcut
    Skip creating the Desktop shortcut.

.EXAMPLE
    pwsh windows/scripts/publish-app.ps1
    # -> windows/dist/BetterScreenshot/BetterScreenshot.App.exe  + Desktop shortcut

.NOTES
    Recording needs ffmpeg on PATH (or windows/tools/ffmpeg.exe, or next to the app). Everything
    else works without it.
#>
[CmdletBinding()]
param(
    [string]$Runtime = 'win-x64',
    [switch]$NoShortcut
)

$ErrorActionPreference = 'Stop'

# Resolve repo paths relative to this script (windows/scripts/ -> windows/ -> repo root).
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDir = Split-Path -Parent $scriptDir
$proj = Join-Path $windowsDir 'src\BetterScreenshot.App\BetterScreenshot.App.csproj'
$outDir = Join-Path $windowsDir 'dist\BetterScreenshot'

Write-Host "Publishing BetterScreenshot ($Runtime, self-contained) ..." -ForegroundColor Cyan
dotnet publish $proj -c Release -r $Runtime --self-contained true -p:PublishSingleFile=false -o $outDir --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

$exe = Join-Path $outDir 'BetterScreenshot.App.exe'
if (-not (Test-Path $exe)) { throw "Expected exe not found: $exe" }
Write-Host "Published: $exe" -ForegroundColor Green

if (-not $NoShortcut) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop 'BetterScreenshot.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($lnkPath)
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $outDir
    $lnk.IconLocation = "$exe,0"
    $lnk.Description = 'BetterScreenshot - free, 100% local screenshot & recording tool (tray app)'
    $lnk.Save()
    Write-Host "Desktop shortcut: $lnkPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Launch it by double-clicking the Desktop shortcut (or run the exe above)." -ForegroundColor Cyan
Write-Host "It lives in the system tray - look for the camera icon; first run shows a welcome + hotkeys." -ForegroundColor DarkGray
