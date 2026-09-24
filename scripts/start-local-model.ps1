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
$statePath = Join-Path $resolvedRoot "data\local-server.json"
$configPath = Join-Path $resolvedRoot "data\config.yaml"
$settingsPath = Join-Path $resolvedRoot "hermes-pocket.json"
$logDir = Join-Path $resolvedRoot "data\logs"
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

$configuredContext = 65536
if ($settings -and $null -ne $settings.context_size) { $configuredContext = [int]$settings.context_size }
elseif ($env:HERMES_CONTEXT_SIZE) { $configuredContext = [int]$env:HERMES_CONTEXT_SIZE }
if ($ContextSize -gt 0) { $configuredContext = $ContextSize }
if ($configuredContext -lt 64000) { throw "context_size must be at least 64000 for Hermes Agent." }
$ContextSize = $configuredContext
$modelPreferredPort = [int](Get-Setting "model_port" 11435)
if ($modelPreferredPort -lt 1 -or $modelPreferredPort -gt 65535) { throw "model_port must be an integer from 1 to 65535." }

$useGpu = [bool](Get-Setting "use_gpu" $false)
$gpuBackend = ([string](Get-Setting "gpu_backend" "cuda")).ToLowerInvariant()
$fallbackToCpu = [bool](Get-Setting "gpu_fallback_to_cpu" $true)
$llamaBackend = if ($useGpu -and $gpuBackend -eq "cuda") { "cuda" } else { "cpu" }
if ($llamaBackend -eq "cuda" -and -not (Test-NvidiaGpu)) {
    if ($fallbackToCpu) {
        Write-Warning "GPU mode is enabled but nvidia-smi was not found. Using the CPU llama.cpp server."
        $llamaBackend = "cpu"
    } else {
        throw "GPU mode is enabled, but nvidia-smi was not found and gpu_fallback_to_cpu is false."
    }
}
$llamaDirectory = if ($llamaBackend -eq "cuda") { "llama-cuda" } else { "llama" }
$llamaServerPath = Join-Path $runtimeRoot "$llamaDirectory\llama-server.exe"
$gpuLayers = [string](Get-Setting "gpu_layers" "all")
$flashAttention = [bool](Get-Setting "flash_attention" $true)
$parallel = [int](Get-Setting "parallel" 1)
if ($parallel -lt 1) { throw "parallel must be at least 1." }

$ollamaSettings = $null
if ($settings -and $settings.PSObject.Properties.Name -contains "ollama") { $ollamaSettings = $settings.ollama }
function Get-OllamaSetting([string]$Name, $Default) {
    if ($ollamaSettings -and $ollamaSettings.PSObject.Properties.Name -contains $Name -and $null -ne $ollamaSettings.$Name) {
        return $ollamaSettings.$Name
    }
    return $Default
}

$ollamaEnabled = [bool](Get-OllamaSetting "enabled" $true)
$ollamaExecutableSetting = [string](Get-OllamaSetting "executable_path" ".cache/runtimes/windows-x64/ollama/ollama.exe")
$ollamaModelsSetting = [string](Get-OllamaSetting "models_directory" "ollamamodel")
$ollamaPreferredPort = [int](Get-OllamaSetting "port" 11434)
$ollamaExecutable = if ([IO.Path]::IsPathRooted($ollamaExecutableSetting)) { $ollamaExecutableSetting } else { Join-Path $resolvedRoot $ollamaExecutableSetting }
$ollamaModelsPath = if ([IO.Path]::IsPathRooted($ollamaModelsSetting)) { $ollamaModelsSetting } else { Join-Path $resolvedRoot $ollamaModelsSetting }

function Stop-ProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-ProcessTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-TrackedServer {
    if (-not (Test-Path -LiteralPath $statePath)) { return }
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $state = $null }
    if ($state -and $state.pid -and $state.server) {
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)" -ErrorAction SilentlyContinue
        $trackedServer = if (Test-Path -LiteralPath $state.server) { (Resolve-Path -LiteralPath $state.server).Path } else { $null }
        if ($processInfo -and $processInfo.ExecutablePath -and $trackedServer -and ((Resolve-Path -LiteralPath $processInfo.ExecutablePath).Path -ieq $trackedServer)) {
            Stop-ProcessTree ([int]$state.pid)
        }
    }
    Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
}

function Get-AvailablePort([int]$PreferredPort) {
    if ($PreferredPort -gt 0) {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $PreferredPort)
            $listener.Start()
            return $PreferredPort
        } catch { }
        finally { if ($listener) { $listener.Stop() } }
    }
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

function Start-OllamaRuntime {
    if (-not $ollamaEnabled) { return $null }
    if (-not (Test-Path -LiteralPath $ollamaExecutable)) {
        throw "Portable Ollama is not installed. Run launch.bat again while online."
    }
    New-Item -ItemType Directory -Force -Path $ollamaModelsPath,$logDir | Out-Null
    $port = Get-AvailablePort $ollamaPreferredPort
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stdoutPath = Join-Path $logDir "ollama-$timestamp.out.log"
    $stderrPath = Join-Path $logDir "ollama-$timestamp.err.log"
    $savedHost = $env:OLLAMA_HOST
    $savedModels = $env:OLLAMA_MODELS
    $savedContext = $env:OLLAMA_CONTEXT_LENGTH
    $savedLibrary = $env:OLLAMA_LLM_LIBRARY
    try {
        $env:OLLAMA_HOST = "127.0.0.1:$port"
        $env:OLLAMA_MODELS = $ollamaModelsPath
        $env:OLLAMA_CONTEXT_LENGTH = [string]$ContextSize
        if ($useGpu) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue }
        else { $env:OLLAMA_LLM_LIBRARY = "cpu" }
        $process = Start-Process -FilePath $ollamaExecutable -ArgumentList @("serve") -WorkingDirectory (Split-Path $ollamaExecutable) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    } finally {
        if ($null -eq $savedHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue } else { $env:OLLAMA_HOST = $savedHost }
        if ($null -eq $savedModels) { Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue } else { $env:OLLAMA_MODELS = $savedModels }
        if ($null -eq $savedContext) { Remove-Item Env:OLLAMA_CONTEXT_LENGTH -ErrorAction SilentlyContinue } else { $env:OLLAMA_CONTEXT_LENGTH = $savedContext }
        if ($null -eq $savedLibrary) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue } else { $env:OLLAMA_LLM_LIBRARY = $savedLibrary }
    }
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { break }
        try {
            $health = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/version" -UseBasicParsing -TimeoutSec 2
            if ($health.StatusCode -eq 200) {
                return [pscustomobject]@{ Process = $process; Port = $port; Executable = $ollamaExecutable }
            }
        } catch { }
    }
    $tail = if (Test-Path -LiteralPath $stderrPath) { (Get-Content -LiteralPath $stderrPath -Tail 30) -join [Environment]::NewLine } else { "No Ollama log was written." }
    if (-not $process.HasExited) { Stop-ProcessTree $process.Id }
    throw "Portable Ollama did not become ready.`n$tail"
}

function Get-OllamaModels($Runtime) {
    if (-not $Runtime) { return @() }
    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$($Runtime.Port)/api/tags" -Method Get -TimeoutSec 10
        return @($response.models | Where-Object { $_.name })
    } catch {
        Write-Warning "Ollama model discovery failed: $($_.Exception.Message)"
        return @()
    }
}

function Select-Model([object[]]$Candidates) {
    if ($ModelPath) {
        $resolvedModel = (Resolve-Path -LiteralPath $ModelPath -ErrorAction Stop).Path
        $match = $Candidates | Where-Object { $_.source -eq "gguf" -and $_.file.FullName -ieq $resolvedModel } | Select-Object -First 1
        if (-not $match) { throw "HERMES_MODEL_PATH is outside the configured model folders: $ModelPath" }
        return $match
    }
    if ($env:HERMES_MODEL) {
        $requested = $env:HERMES_MODEL
        $match = $Candidates | Where-Object { $_.name -ieq $requested -or $_.id -ieq $requested -or $_.id -ieq ("ollama:" + $requested) } | Select-Object -First 1
        if (-not $match) { throw "HERMES_MODEL did not match an installed GGUF or Ollama model: $requested" }
        return $match
    }
    if ($Candidates.Count -eq 1) { return $Candidates[0] }
    Write-Host "Available models:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $sizeText = if ($Candidates[$i].size) { " ($([math]::Round([double]$Candidates[$i].size / 1GB, 2)) GB)" } else { "" }
        Write-Host ("  [{0}] [{1}] {2}{3}" -f ($i + 1), $Candidates[$i].source, $Candidates[$i].name, $sizeText)
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
        $before = @(); $after = @()
        if ($start -gt 0) { $before = @($lines[0..($start - 1)]) }
        if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
        $lines = @($before + $replacement + $after)
    } else {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[-1])) { $lines += "" }
        $lines += $replacement
    }
    Set-Content -LiteralPath $configPath -Value ($lines -join [Environment]::NewLine) -Encoding utf8
}

New-Item -ItemType Directory -Force -Path (Split-Path $configPath),$logDir | Out-Null
Stop-TrackedServer
$ollamaRuntime = $null
if ($ollamaEnabled) {
    try { $ollamaRuntime = Start-OllamaRuntime }
    catch { Write-Warning $_.Exception.Message }
}

$choices = @()
foreach ($file in @(Get-ModelCandidates)) {
    $choices += [pscustomobject]@{ id = $file.Name; name = $file.Name; source = "gguf"; file = $file; size = $file.Length }
}
foreach ($item in @(Get-OllamaModels $ollamaRuntime)) {
    $choices += [pscustomobject]@{ id = "ollama:$($item.name)"; name = $item.name; source = "ollama"; file = $null; size = $item.size }
}
if ($choices.Count -eq 0) {
    if ($ollamaRuntime) { Stop-ProcessTree $ollamaRuntime.Process.Id }
    throw "No GGUF or Ollama models found. Put a .gguf file in the portable model folder or run ollama-model.cmd pull <model>."
}

$selected = Select-Model $choices
if ($selected.source -eq "ollama") {
    if (-not $ollamaRuntime) { throw "The selected Ollama model could not be loaded because the portable Ollama server is unavailable." }
    $modelId = $selected.name
    $port = $ollamaRuntime.Port
    $process = $ollamaRuntime.Process
    $serverPath = $ollamaRuntime.Executable
    $backend = if ($useGpu) { "ollama-gpu" } else { "ollama-cpu" }
} else {
    if ($ollamaRuntime) { Stop-ProcessTree $ollamaRuntime.Process.Id }
    if (-not (Test-Path -LiteralPath $llamaServerPath)) {
        throw "llama-server.exe is not installed. Run launch.bat again so the configured llama.cpp bundle can be installed."
    }
    $modelId = [System.IO.Path]::GetFileNameWithoutExtension($selected.file.Name) -replace '[^A-Za-z0-9._:-]', '-'
    if ([string]::IsNullOrWhiteSpace($modelId)) { $modelId = "local" }
    $port = Get-AvailablePort $modelPreferredPort
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stdoutPath = Join-Path $logDir "llama-server-$timestamp.out.log"
    $stderrPath = Join-Path $logDir "llama-server-$timestamp.err.log"
    $arguments = @(
        "--model", $selected.file.FullName,
        "--host", "127.0.0.1",
        "--port", $port,
        "--ctx-size", $ContextSize,
        "--parallel", $parallel,
        "--jinja",
        "--alias", $modelId
    )
    if ($llamaBackend -eq "cuda") {
        $arguments += @("--n-gpu-layers", $gpuLayers)
        if ($flashAttention) { $arguments += @("--flash-attn", "on") }
    } else {
        $arguments += @("--n-gpu-layers", "0")
    }
    $process = Start-Process -FilePath $llamaServerPath -ArgumentList $arguments -WorkingDirectory (Split-Path $llamaServerPath) -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
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
        if (-not $process.HasExited) { Stop-ProcessTree $process.Id }
        throw "llama-server did not become ready for '$($selected.name)'.`n$tail"
    }
    $backend = "llama.cpp-$llamaBackend"
    $serverPath = $llamaServerPath
}

Update-HermesConfig $modelId $port $ContextSize
@{
    pid = $process.Id
    port = $port
    model = if ($selected.source -eq "ollama") { $selected.name } else { $selected.file.FullName }
    model_id = $modelId
    source = $selected.source
    backend = $backend
    context_size = $ContextSize
    parallel = if ($selected.source -eq "gguf") { $parallel } else { 1 }
    server = $serverPath
    started_at = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding utf8

Write-Host "Local model ready: $($selected.name)" -ForegroundColor Green
Write-Host "Backend: $backend | Context: $ContextSize | Source: $($selected.source)" -ForegroundColor DarkGray
Write-Host "Hermes endpoint: http://127.0.0.1:$port/v1" -ForegroundColor DarkGray
