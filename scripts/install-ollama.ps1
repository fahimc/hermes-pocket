[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$settingsPath = Join-Path $resolvedRoot "hermes-pocket.json"
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
    try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse $settingsPath : $($_.Exception.Message)" }
}

$ollamaSettings = $null
if ($settings -and $settings.PSObject.Properties.Name -contains "ollama") { $ollamaSettings = $settings.ollama }
function Get-OllamaSetting([string]$Name, $Default) {
    if ($ollamaSettings -and $ollamaSettings.PSObject.Properties.Name -contains $Name -and $null -ne $ollamaSettings.$Name) {
        return $ollamaSettings.$Name
    }
    return $Default
}

if (-not [bool](Get-OllamaSetting "enabled" $true)) {
    Write-Host "Portable Ollama is disabled in hermes-pocket.json." -ForegroundColor DarkGray
    exit 0
}

$executableSetting = [string](Get-OllamaSetting "executable_path" ".cache/runtimes/windows-x64/ollama/ollama.exe")
$modelsSetting = [string](Get-OllamaSetting "models_directory" "ollamamodel")
$executablePath = if ([IO.Path]::IsPathRooted($executableSetting)) { $executableSetting } else { Join-Path $resolvedRoot $executableSetting }
$modelsPath = if ([IO.Path]::IsPathRooted($modelsSetting)) { $modelsSetting } else { Join-Path $resolvedRoot $modelsSetting }
$targetDirectory = Split-Path -Parent $executablePath
$downloadRoot = Join-Path $resolvedRoot ".cache\downloads"
$tempRoot = Join-Path $resolvedRoot ".tmp\ollama-extract"
$archive = Join-Path $downloadRoot "ollama-windows-amd64.zip"

New-Item -ItemType Directory -Force -Path $downloadRoot,$targetDirectory,$modelsPath | Out-Null
if (-not (Test-Path -LiteralPath $executablePath)) {
    $headers = @{ "User-Agent" = "hermes-pocket-setup" }
    $release = Invoke-RestMethod "https://api.github.com/repos/ollama/ollama/releases/latest" -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -eq "ollama-windows-amd64.zip" } | Select-Object -First 1
    if (-not $asset) { throw "The latest Ollama release has no standalone Windows x64 ZIP." }

    $validArchive = (Test-Path -LiteralPath $archive) -and ((Get-Item -LiteralPath $archive).Length -eq [int64]$asset.size)
    if ($validArchive -and [string]$asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
        $validArchive = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ieq $Matches[1]
    }
    if (-not $validArchive) {
        Write-Host "Downloading Ollama $($release.tag_name) ($([math]::Round($asset.size / 1GB, 2)) GB)..." -ForegroundColor Cyan
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -L -f --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 3600 -o $archive $asset.browser_download_url
            if ($LASTEXITCODE -ne 0) { throw "curl failed to download Ollama." }
        } else {
            Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $archive -UseBasicParsing -TimeoutSec 3600
        }
    }
    if ((Get-Item -LiteralPath $archive).Length -ne [int64]$asset.size) { throw "Ollama archive size did not match the release metadata." }
    if ([string]$asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actualHash -ine $Matches[1]) { throw "Ollama archive SHA-256 checksum did not match the release metadata." }
    }

    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $tempRoot -Force
    $sourceExe = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter "ollama.exe" -File | Select-Object -First 1
    if (-not $sourceExe) { throw "The Ollama archive did not contain ollama.exe." }
    Copy-Item -Path (Join-Path $sourceExe.DirectoryName "*") -Destination $targetDirectory -Recurse -Force
    if (-not (Test-Path -LiteralPath $executablePath)) { throw "Ollama installation did not produce $executablePath." }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Write-Host "Portable Ollama installed in $targetDirectory" -ForegroundColor Green
} else {
    Write-Host "Portable Ollama is already installed." -ForegroundColor Green
}

New-Item -ItemType Directory -Force -Path $modelsPath | Out-Null
