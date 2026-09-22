[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [ValidateSet("auto", "cpu", "cuda")]
    [string]$Backend = "auto"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$runtimeRoot = Join-Path $resolvedRoot ".cache\runtimes\windows-x64"
$downloadRoot = Join-Path $resolvedRoot ".cache\downloads"
$settingsPath = Join-Path $resolvedRoot "hermes-pocket.json"
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
    try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse $settingsPath : $($_.Exception.Message)" }
}

function Get-Setting([string]$Name, $Default) {
    if ($settings -and $settings.PSObject.Properties.Name -contains $Name -and $null -ne $settings.$Name) {
        return $settings.$Name
    }
    return $Default
}

function Test-NvidiaGpu {
    return $null -ne (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)
}

$useGpu = [bool](Get-Setting "use_gpu" $false)
$configuredBackend = ([string](Get-Setting "gpu_backend" "cuda")).ToLowerInvariant()
$fallbackToCpu = [bool](Get-Setting "gpu_fallback_to_cpu" $true)
if ($Backend -eq "auto") {
    $Backend = if ($useGpu -and $configuredBackend -eq "cuda") { "cuda" } else { "cpu" }
}
if ($Backend -eq "cuda" -and -not (Test-NvidiaGpu)) {
    if ($fallbackToCpu) {
        Write-Warning "GPU mode is enabled but nvidia-smi was not found. Falling back to the CPU llama.cpp bundle."
        $Backend = "cpu"
    } else {
        throw "GPU mode is enabled, but nvidia-smi was not found and gpu_fallback_to_cpu is false."
    }
}

$cpuArchive = Join-Path $downloadRoot "llama-b10938-bin-win-cpu-x64.zip"
$cpuDestination = Join-Path $runtimeRoot "llama"
$cpuUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b10938/llama-b10938-bin-win-cpu-x64.zip"
$cudaArchive = Join-Path $downloadRoot "llama-b10938-bin-win-cuda-13.3-x64.zip"
$cudaRuntimeArchive = Join-Path $downloadRoot "cudart-llama-bin-win-cuda-13.3-x64.zip"
$cudaDestination = Join-Path $runtimeRoot "llama-cuda"
$cudaUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b10938/llama-b10938-bin-win-cuda-13.3-x64.zip"
$cudaRuntimeUrl = "https://github.com/ggml-org/llama.cpp/releases/download/b10938/cudart-llama-bin-win-cuda-13.3-x64.zip"

New-Item -ItemType Directory -Force -Path $downloadRoot,$runtimeRoot | Out-Null
function Download-Asset([string]$Url, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        $existing = Get-Item -LiteralPath $Destination
        if ($existing.Length -gt 0) { return }
        Remove-Item -LiteralPath $Destination -Force
    }
    Write-Host "Downloading $(Split-Path $Url -Leaf)..." -ForegroundColor Cyan
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L -f --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 1800 -o $Destination $Url
        if ($LASTEXITCODE -ne 0) { throw "curl failed to download $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 1800
    }
    if (-not (Test-Path -LiteralPath $Destination) -or (Get-Item -LiteralPath $Destination).Length -eq 0) {
        throw "Downloaded asset is missing or empty: $Url"
    }
}

function Install-Bundle([string]$Name, [string]$Archive, [string]$Url, [string]$Destination) {
    if (Test-Path -LiteralPath (Join-Path $Destination "llama-server.exe")) {
        Write-Host "llama.cpp $Name bundle is already installed." -ForegroundColor Green
        return
    }
    Download-Asset $Url $Archive
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    if (-not (Test-Path -LiteralPath (Join-Path $Destination "llama-server.exe"))) {
        throw "The llama.cpp $Name archive did not contain llama-server.exe."
    }
}

if ($Backend -eq "cuda") {
    if (-not (Test-Path -LiteralPath (Join-Path $cudaDestination "llama-server.exe"))) {
        Download-Asset $cudaUrl $cudaArchive
        Download-Asset $cudaRuntimeUrl $cudaRuntimeArchive
        if (Test-Path -LiteralPath $cudaDestination) { Remove-Item -LiteralPath $cudaDestination -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $cudaDestination | Out-Null
        Expand-Archive -LiteralPath $cudaArchive -DestinationPath $cudaDestination -Force
        Expand-Archive -LiteralPath $cudaRuntimeArchive -DestinationPath $cudaDestination -Force
        if (-not (Test-Path -LiteralPath (Join-Path $cudaDestination "llama-server.exe"))) {
            throw "The llama.cpp CUDA archive did not contain llama-server.exe."
        }
        Write-Host "llama.cpp CUDA 13.3 bundle installed in $cudaDestination" -ForegroundColor Green
    } else {
        Write-Host "llama.cpp CUDA bundle is already installed." -ForegroundColor Green
    }
} else {
    Install-Bundle "CPU" $cpuArchive $cpuUrl $cpuDestination
}
