[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$runtimeRoot = Join-Path $resolvedRoot ".cache\runtimes\windows-x64"
$downloadRoot = Join-Path $resolvedRoot ".cache\downloads"
$archive = Join-Path $downloadRoot "llama-b10938-bin-win-cpu-x64.zip"
$destination = Join-Path $runtimeRoot "llama"
$url = "https://github.com/ggml-org/llama.cpp/releases/download/b10938/llama-b10938-bin-win-cpu-x64.zip"

New-Item -ItemType Directory -Force -Path $downloadRoot,$runtimeRoot | Out-Null
if (-not (Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -eq 0) {
    Write-Host "Downloading official llama.cpp CPU runtime..." -ForegroundColor Cyan
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L -f --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 1200 -o $archive $url
        if ($LASTEXITCODE -ne 0) { throw "curl failed to download llama.cpp." }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing -TimeoutSec 1200
    }
}

if (Test-Path -LiteralPath (Join-Path $destination "llama-server.exe")) {
    Write-Host "llama-server is already installed." -ForegroundColor Green
    exit 0
}

if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force
if (-not (Test-Path -LiteralPath (Join-Path $destination "llama-server.exe"))) {
    throw "The llama.cpp archive did not contain llama-server.exe."
}
Write-Host "llama-server installed in $destination" -ForegroundColor Green
