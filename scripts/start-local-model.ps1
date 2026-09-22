[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [string]$ModelPath,
    [int]$ContextSize = 0
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$runtimeRoot = Join-Path $resolvedRoot ".cache\runtimes\windows-x64"
$serverPath = Join-Path $runtimeRoot "llama\llama-server.exe"
$statePath = Join-Path $resolvedRoot "data\local-server.json"
$configPath = Join-Path $resolvedRoot "data\config.yaml"
$settingsPath = Join-Path $resolvedRoot "hermes-pocket.json"
$logDir = Join-Path $resolvedRoot "data\logs"
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
    try { $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse $settingsPath : $($_.Exception.Message)" }
}
$configuredContext = 65536
if ($settings -and $null -ne $settings.context_size) { $configuredContext = [int]$settings.context_size }
elseif ($env:HERMES_CONTEXT_SIZE) { $configuredContext = [int]$env:HERMES_CONTEXT_SIZE }
if ($ContextSize -gt 0) { $configuredContext = $ContextSize }
if ($configuredContext -lt 64000) { throw "context_size must be at least 64000 for Hermes Agent." }
$ContextSize = $configuredContext

function Stop-TrackedServer {
    if (-not (Test-Path -LiteralPath $statePath)) { return }
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
    if ($state -and $state.pid) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)" -ErrorAction SilentlyContinue
        if ($processInfo -and $processInfo.ExecutablePath -and ((Resolve-Path -LiteralPath $processInfo.ExecutablePath).Path -ieq (Resolve-Path -LiteralPath $serverPath).Path)) {
            Stop-Process -Id ([int]$state.pid) -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Get-ModelCandidates {
    $roots = @()
    if ($settings -and $settings.model_directory) {
        foreach ($configuredRoot in @($settings.model_directory)) {
            if ([System.IO.Path]::IsPathRooted([string]$configuredRoot)) { $roots += [string]$configuredRoot }
            else { $roots += Join-Path $resolvedRoot ([string]$configuredRoot) }
        }
    } elseif ($env:HERMES_MODELS_DIR) {
        $roots += $env:HERMES_MODELS_DIR
    } else {
        foreach ($relative in @("models", "model")) {
            $candidate = Join-Path $resolvedRoot $relative
            if (Test-Path -LiteralPath $candidate) { $roots += $candidate }
        }
    }
    $files = @()
    foreach ($rootPath in $roots) {
        if (-not (Test-Path -LiteralPath $rootPath)) { continue }
        $files += Get-ChildItem -LiteralPath $rootPath -Filter "*.gguf" -File -Recurse -ErrorAction SilentlyContinue
    }
    @($files | Sort-Object FullName -Unique)
}

function Select-Model([object[]]$Candidates) {
    if ($ModelPath) {
        $resolvedModel = (Resolve-Path -LiteralPath $ModelPath -ErrorAction Stop).Path
        $match = $Candidates | Where-Object { $_.FullName -ieq $resolvedModel } | Select-Object -First 1
        if (-not $match) { throw "HERMES_MODEL_PATH is outside the configured model folders: $ModelPath" }
        return $match
    }
    if ($env:HERMES_MODEL) {
        $requested = $env:HERMES_MODEL
        $match = $Candidates | Where-Object { $_.Name -ieq $requested -or $_.FullName -ieq $requested } | Select-Object -First 1
        if (-not $match) { throw "HERMES_MODEL did not match a .gguf file: $requested" }
        return $match
    }
    if ($Candidates.Count -eq 1) { return $Candidates[0] }
    Write-Host "Available GGUF models:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $sizeGb = [math]::Round($Candidates[$i].Length / 1GB, 2)
        Write-Host ("  [{0}] {1} ({2} GB)" -f ($i + 1), $Candidates[$i].Name, $sizeGb)
    }
    do {
        $choice = Read-Host "Choose a model number"
        $parsed = 0
        $valid = [int]::TryParse($choice, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $Candidates.Count
    } until ($valid)
    return $Candidates[$parsed - 1]
}

function Update-HermesConfig([string]$ModelId, [int]$Port, [int]$Context) {
    $lines = @()
    if (Test-Path -LiteralPath $configPath) { $lines = @(Get-Content -LiteralPath $configPath) }
    $replacement = @(
        "model:",
        "  default: $ModelId",
        "  provider: custom",
        "  base_url: http://127.0.0.1:$Port/v1",
        "  api_mode: chat_completions",
        "  context_length: $Context"
    )
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^model:\s*$') { $start = $i; break }
    }
    if ($start -ge 0) {
        $end = $start + 1
        while ($end -lt $lines.Count -and ($lines[$end] -match '^\s' -or [string]::IsNullOrWhiteSpace($lines[$end]))) { $end++ }
        $before = @()
        $after = @()
        if ($start -gt 0) { $before = @($lines[0..($start - 1)]) }
        if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
        $lines = @($before + $replacement + $after)
    } else {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) { $lines += "" }
        $lines += $replacement
    }
    Set-Content -LiteralPath $configPath -Value ($lines -join [Environment]::NewLine) -Encoding utf8
}

if (-not (Test-Path -LiteralPath $serverPath)) {
    throw "llama-server.exe is not installed. Run launch.bat again so the setup can download it."
}
New-Item -ItemType Directory -Force -Path (Split-Path $configPath),$logDir | Out-Null
Stop-TrackedServer
$candidates = @(Get-ModelCandidates)
if ($candidates.Count -eq 0) {
    throw "No .gguf models found. Put a model in the portable model or models folder, or set HERMES_MODELS_DIR."
}
$selected = Select-Model $candidates
$modelId = [System.IO.Path]::GetFileNameWithoutExtension($selected.Name) -replace '[^A-Za-z0-9._:-]', '-'
if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = "local" }
$port = Get-FreePort
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutPath = Join-Path $logDir "llama-server-$timestamp.out.log"
$stderrPath = Join-Path $logDir "llama-server-$timestamp.err.log"
$arguments = @("--model", $selected.FullName, "--host", "127.0.0.1", "--port", $port, "--ctx-size", $ContextSize, "--jinja", "--alias", $modelId)
$process = Start-Process -FilePath $serverPath -ArgumentList $arguments -WorkingDirectory (Split-Path $serverPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru

$ready = $false
for ($i = 0; $i -lt 240; $i++) {
    Start-Sleep -Milliseconds 500
    if ($process.HasExited) { break }
    try {
        $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2
        if ($health.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
}
if (-not $ready) {
    $tail = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Tail 20) -join [Environment]::NewLine } else { "No server log was written." }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    throw "llama-server did not become ready for '$($selected.Name)'.`n$tail"
}

Update-HermesConfig $modelId $port $ContextSize
@{
    pid = $process.Id
    port = $port
    model = $selected.FullName
    model_id = $modelId
    server = $serverPath
    started_at = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

Write-Host "Local model ready: $($selected.Name)" -ForegroundColor Green
Write-Host "Hermes endpoint: http://127.0.0.1:$port/v1" -ForegroundColor DarkGray
