[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$cacheRoot = Join-Path $resolvedRoot ".cache"
$runtimeRoot = Join-Path $cacheRoot "runtimes\windows-x64"
$downloadRoot = Join-Path $cacheRoot "downloads"
$tempRoot = Join-Path $resolvedRoot ".tmp"
$sourceRoot = Join-Path $resolvedRoot "src"
$sourceDestination = Join-Path $sourceRoot "hermes-agent"
$runtimeBin = Join-Path $runtimeRoot "bin"
$readyFlag = Join-Path $runtimeRoot "ready.flag"

$pythonUrl = "https://github.com/astral-sh/python-build-standalone/releases/download/20260602/cpython-3.11.15+20260602-x86_64-pc-windows-msvc-install_only.tar.gz"
$nodeUrl = "https://nodejs.org/dist/v22.22.3/node-v22.22.3-win-x64.zip"
$uvUrl = "https://github.com/astral-sh/uv/releases/download/0.11.19/uv-x86_64-pc-windows-msvc.zip"
$rgUrl = "https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-pc-windows-msvc.zip"
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/MinGit-2.54.0-64-bit.zip"
$hermesCommit = "743ee72596e7a9f23bc7cd5c570a6ebd958043e4"
$hermesUrl = "https://github.com/NousResearch/hermes-agent/archive/$hermesCommit.zip"

function Write-Step([string]$Message) { Write-Host "`n[SETUP] $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN]  $Message" -ForegroundColor Yellow }

function Download-Asset([string]$Url, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination
        if ($existing.Length -gt 0) { Write-Host "        Cached: $(Split-Path $Url -Leaf)"; return }
        Remove-Item -LiteralPath $Destination -Force
    }
    Write-Host "        Downloading $(Split-Path $Url -Leaf) ..." -ForegroundColor DarkCyan
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L -f --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 1200 -o $Destination $Url
        if ($LASTEXITCODE -ne 0) { throw "curl failed for $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 1200
    }
    if (-not (Test-Path -LiteralPath $Destination) -or (Get-Item -LiteralPath $Destination).Length -eq 0) {
        throw "Downloaded asset is missing or empty: $Url"
    }
}

function Extract-TarGz([string]$Archive, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & tar.exe -m -xzf $Archive -C $Destination --strip-components=1
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $Archive" }
}

function Extract-Zip([string]$Archive, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    if (-not (Get-ChildItem -LiteralPath $Destination -Force | Select-Object -First 1)) { throw "Archive was empty: $Archive" }
}

function Move-FirstDirectoryContents([string]$Source, [string]$Destination) {
    $child = Get-ChildItem -LiteralPath $Source -Directory | Select-Object -First 1
    if ($child) {
        if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
        Move-Item -LiteralPath $child.FullName -Destination $Destination
    } else {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
    }
}

New-Item -ItemType Directory -Force -Path $runtimeRoot,$downloadRoot,$tempRoot,$sourceRoot,$runtimeBin,(Join-Path $resolvedRoot "data") | Out-Null

Write-Step "Portable Python 3.11"
$pythonArchive = Join-Path $downloadRoot "python.tar.gz"
Download-Asset $pythonUrl $pythonArchive
Extract-TarGz $pythonArchive (Join-Path $runtimeRoot "python")
if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot "python\python.exe"))) { throw "Portable Python verification failed." }
Write-Ok "Python ready"

Write-Step "Node.js 22 LTS"
$nodeArchive = Join-Path $downloadRoot "node.zip"
Download-Asset $nodeUrl $nodeArchive
Extract-Zip $nodeArchive (Join-Path $tempRoot "node")
Move-FirstDirectoryContents (Join-Path $tempRoot "node") (Join-Path $runtimeRoot "node")
& (Join-Path $runtimeRoot "node\node.exe") --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Node.js verification failed." }
Write-Ok "Node.js ready"

Write-Step "uv package manager"
$uvArchive = Join-Path $downloadRoot "uv.zip"
Download-Asset $uvUrl $uvArchive
Extract-Zip $uvArchive (Join-Path $runtimeRoot "uv")
$uvExe = Get-ChildItem -LiteralPath (Join-Path $runtimeRoot "uv") -Filter "uv.exe" -File -Recurse | Select-Object -First 1
if (-not $uvExe) { throw "uv.exe was not found after extraction." }
Write-Ok "uv ready"

Write-Step "ripgrep and portable Git"
$rgArchive = Join-Path $downloadRoot "ripgrep.zip"
Download-Asset $rgUrl $rgArchive
Extract-Zip $rgArchive (Join-Path $tempRoot "ripgrep")
$rgExe = Get-ChildItem -LiteralPath (Join-Path $tempRoot "ripgrep") -Filter "rg.exe" -File -Recurse | Select-Object -First 1
if ($rgExe) { Copy-Item -LiteralPath $rgExe.FullName -Destination (Join-Path $runtimeBin "rg.exe") -Force }
$gitArchive = Join-Path $downloadRoot "mingit.zip"
Download-Asset $gitUrl $gitArchive
Extract-Zip $gitArchive (Join-Path $runtimeRoot "git")
Write-Ok "CLI helpers ready"

Write-Step "Hermes Agent source at commit $hermesCommit"
$hermesArchive = Join-Path $downloadRoot "hermes-agent-$hermesCommit.zip"
Download-Asset $hermesUrl $hermesArchive
Extract-Zip $hermesArchive (Join-Path $tempRoot "hermes")
$hermesFolder = Get-ChildItem -LiteralPath (Join-Path $tempRoot "hermes") -Directory | Select-Object -First 1
if (-not $hermesFolder) { throw "Hermes source archive did not contain a source directory." }
if (Test-Path -LiteralPath $sourceDestination) { Remove-Item -LiteralPath $sourceDestination -Recurse -Force }
New-Item -ItemType Directory -Force -Path $sourceDestination | Out-Null
Copy-Item -Path (Join-Path $hermesFolder.FullName "*") -Destination $sourceDestination -Recurse -Force
if (-not (Test-Path -LiteralPath (Join-Path $sourceDestination "hermes_cli"))) { throw "Hermes source verification failed." }
Write-Ok "Hermes source ready"

Write-Step "Python virtual environment and Hermes dependencies"
$pythonExe = Join-Path $runtimeRoot "python\python.exe"
$venvDir = Join-Path $runtimeRoot "venv"
& $uvExe.FullName venv $venvDir --python $pythonExe
if ($LASTEXITCODE -ne 0) { throw "Could not create the portable virtual environment." }
$venvPython = Join-Path $venvDir "Scripts\python.exe"
& $uvExe.FullName pip install --python $venvPython --link-mode=copy -e "$sourceDestination[all]"
if ($LASTEXITCODE -ne 0) { throw "Hermes dependency installation failed." }
& $uvExe.FullName pip install --python $venvPython --link-mode=copy "anthropic>=0.39.0" "python-telegram-bot[webhooks]==22.6"
if ($LASTEXITCODE -ne 0) { Write-Warn "Optional provider/messaging extras did not install; Hermes can retry them later." }
Write-Ok "Hermes dependencies ready"

Write-Step "Optional browser runtime"
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $runtimeRoot "playwright"
& $venvPython -m playwright install chromium
if ($LASTEXITCODE -ne 0) { Write-Warn "Chromium install failed; terminal and non-browser tools remain available." }

Set-Content -LiteralPath $readyFlag -Value "Hermes source: $hermesCommit" -Encoding utf8
Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`nSetup complete. Run launch.bat again to open Hermes Pocket." -ForegroundColor Green
