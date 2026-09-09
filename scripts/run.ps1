<#
    WebScripts — چلول (Windows)

        powershell -ExecutionPolicy Bypass -File scripts\run.ps1

    ټاکنې:
        -BackendOnly   یوازې د Python سرور وچلوه (بې ظاهري برنامې)
#>

param(
    [switch]$BackendOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'backend'
$frontend = Join-Path $root 'frontend'
$venvPython = Join-Path $backend '.venv\Scripts\python.exe'

if (-not (Test-Path $venvPython)) {
    throw 'لومړی scripts\setup.ps1 وچلوئ.'
}

if ($BackendOnly) {
    Push-Location $backend
    try { & $venvPython 'run_server.py' } finally { Pop-Location }
    return
}

# The Flutter app starts the backend itself; this variable tells it which
# interpreter to use so it never picks a wrong system Python.
$env:WEBSCRIPTS_PYTHON = $venvPython

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter ونه موندل شو. یا یې نصب کړئ یا -BackendOnly وکاروئ.'
}

Push-Location $frontend
try {
    flutter run -d windows
} finally {
    Pop-Location
}
