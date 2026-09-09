<#
    Builds the same single .exe locally that the GitHub Actions workflow
    produces (.github/workflows/build-windows.yml).

        powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1

    Needs: Python 3.10+, Flutter (with the Windows toolchain), Inno Setup 6.
    The result lands in dist\WebScripts-Setup-<version>-x64.exe
#>

param(
    [string]$Version = "0.1.0",
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }

# ---------------------------------------------------------------- backend ---

Write-Step 'د Python چاپېریال چمتو کول'
$venvPython = Join-Path $root 'backend\.venv\Scripts\python.exe'
if (-not (Test-Path $venvPython)) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\setup.ps1')
}
& $venvPython -m pip install --quiet pyinstaller

Write-Step 'backend یو exe ته بدلول'
Push-Location (Join-Path $root 'backend')
try {
    & $venvPython -m PyInstaller ..\packaging\webscripts-backend.spec `
        --noconfirm --distpath ..\dist\backend --workpath ..\build\pyinstaller
} finally {
    Pop-Location
}

# --------------------------------------------------------------- frontend ---

Write-Step 'د Flutter وینډوز نسخه جوړول'
Push-Location (Join-Path $root 'frontend')
try {
    if (-not (Test-Path 'windows')) {
        flutter create --platforms=windows --project-name web_scripts .
    }
    flutter pub get
    flutter build windows --release
} finally {
    Pop-Location
}

# -------------------------------------------------------------- packaging ---

Write-Step 'د برنامې فولډر راټولول'
$release = Join-Path $root 'frontend\build\windows\x64\runner\Release'
if (-not (Test-Path $release)) {
    $release = Join-Path $root 'frontend\build\windows\runner\Release'
}
$appDir = Join-Path $root 'dist\app'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
Copy-Item "$release\*" $appDir -Recurse -Force
Copy-Item (Join-Path $root 'dist\backend\webscripts-backend.exe') $appDir -Force
Copy-Item (Join-Path $root 'README.md') $appDir -Force

if ($SkipInstaller) {
    Write-Host "`nچمتو: $appDir" -ForegroundColor Green
    return
}

Write-Step 'یو واحد installer exe جوړول'
$iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files\Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $iscc)) {
    throw 'Inno Setup 6 ونه موندل شو. له https://jrsoftware.org/isdl.php نه یې نصب کړئ.'
}
& $iscc (Join-Path $root 'packaging\installer.iss') `
    "/DAppVersion=$Version" "/DSourceDir=..\dist\app" "/DOutputDir=..\dist"

Write-Host "`nچمتو دی:" -ForegroundColor Green
Get-ChildItem (Join-Path $root 'dist\*.exe') | ForEach-Object {
    Write-Host ("  {0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB))
}
