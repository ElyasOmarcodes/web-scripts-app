<#
    WebScripts — د لومړي ځل چمتووالی (Windows)

    دا سکریپټ:
      1. د Python مجازي چاپېریال (.venv) جوړوي او اړین کڅوړې نصبوي
      2. د Flutter اړتیاوې راکوزوي او د وینډوز برخه جوړوي
      3. ګوري چې Microsoft Edge نصب دی که نه

    چلول:  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'backend'
$frontend = Join-Path $root 'frontend'

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Warn($text) { Write-Host "!!  $text" -ForegroundColor Yellow }

# ---------------------------------------------------------------- Python ----

Write-Step 'د Python لټون'
$python = $null
foreach ($candidate in @('py', 'python')) {
    $found = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($found) { $python = $found.Source; break }
}
if (-not $python) {
    throw 'Python ونه موندل شو. له https://www.python.org/downloads/ نه Python 3.10+ نصب کړئ.'
}
Write-Host "    $python"

Write-Step 'مجازي چاپېریال جوړول (.venv)'
$venv = Join-Path $backend '.venv'
if (-not (Test-Path $venv)) {
    & $python -m venv $venv
}
$venvPython = Join-Path $venv 'Scripts\python.exe'

Write-Step 'د Python کڅوړې نصبول'
& $venvPython -m pip install --upgrade pip --quiet
& $venvPython -m pip install -r (Join-Path $backend 'requirements.txt')

# ------------------------------------------------------------------ Edge ----

Write-Step 'د Microsoft Edge کتنه'
$edgePaths = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
)
if ($edgePaths | Where-Object { Test-Path $_ }) {
    Write-Host '    Edge موجود دی ✔'
} else {
    Write-Warn 'Edge ونه موندل شو. مهرباني وکړئ Microsoft Edge نصب کړئ.'
}

# --------------------------------------------------------------- Flutter ----

Write-Step 'د Flutter کتنه'
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutter) {
    Push-Location $frontend
    try {
        if (-not (Test-Path (Join-Path $frontend 'windows'))) {
            Write-Step 'د وینډوز برخه جوړېږي (flutter create)'
            flutter create --platforms=windows --project-name web_scripts .
        }
        Write-Step 'flutter pub get'
        flutter pub get
    } finally {
        Pop-Location
    }
} else {
    Write-Warn 'Flutter ونه موندل شو — ظاهري برنامه به کار ونه کړي.'
    Write-Warn 'خو backend یوازې هم کار کوي:  .venv\Scripts\python.exe -m webscripts.cli record --url https://facebook.com'
}

Write-Host ''
Write-Host 'چمتو دی! اوس دا وچلوئ:  powershell -ExecutionPolicy Bypass -File scripts\run.ps1' -ForegroundColor Green
