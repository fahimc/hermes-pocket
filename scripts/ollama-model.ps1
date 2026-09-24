[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Command
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$settingsPath = Join-Path $resolvedRoot "hermes-pocket.json"
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$ollamaSettings = $settings.ollama
$enabled = if ($null -eq $ollamaSettings.enabled) { $true } else { [bool]$ollamaSettings.enabled }
if (-not $enabled) { throw "Portable Ollama is disabled in hermes-pocket.json." }
$executableSetting = if ($ollamaSettings.executable_path) { [string]$ollamaSettings.executable_path } else { ".cache/runtimes/windows-x64/ollama/ollama.exe" }
$modelsSetting = if ($ollamaSettings.models_directory) { [string]$ollamaSettings.models_directory } else { "ollamamodel" }
$preferredPort = if ($ollamaSettings.port) { [int]$ollamaSettings.port } else { 11434 }
$contextSize = [int]$settings.context_size
$executable = if ([IO.Path]::IsPathRooted($executableSetting)) { $executableSetting } else { Join-Path $resolvedRoot $executableSetting }
$modelsPath = if ([IO.Path]::IsPathRooted($modelsSetting)) { $modelsSetting } else { Join-Path $resolvedRoot $modelsSetting }
$statePath = Join-Path $resolvedRoot "data\local-server.json"
$logDir = Join-Path $resolvedRoot "data\logs"

function Stop-ProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-ProcessTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Get-AvailablePort([int]$PreferredPort) {
    if ($PreferredPort -gt 0) {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $PreferredPort)
            $listener.Start(); return $PreferredPort
        } catch { }
        finally { if ($listener) { $listener.Stop() } }
    }
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Start-Server {
    if (-not (Test-Path -LiteralPath $executable)) { throw "Portable Ollama is missing. Run launch.bat while online." }
    New-Item -ItemType Directory -Force -Path $modelsPath,$logDir | Out-Null
    $port = Get-AvailablePort $preferredPort
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stdout = Join-Path $logDir "ollama-manager-$stamp.out.log"
    $stderr = Join-Path $logDir "ollama-manager-$stamp.err.log"
    $savedHost = $env:OLLAMA_HOST; $savedModels = $env:OLLAMA_MODELS; $savedContext = $env:OLLAMA_CONTEXT_LENGTH; $savedLibrary = $env:OLLAMA_LLM_LIBRARY
    try {
        $env:OLLAMA_HOST = "127.0.0.1:$port"
        $env:OLLAMA_MODELS = $modelsPath
        $env:OLLAMA_CONTEXT_LENGTH = [string]$contextSize
        if ([bool]$settings.use_gpu) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue } else { $env:OLLAMA_LLM_LIBRARY = "cpu" }
        $process = Start-Process -FilePath $executable -ArgumentList @("serve") -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    } finally {
        if ($null -eq $savedHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue } else { $env:OLLAMA_HOST = $savedHost }
        if ($null -eq $savedModels) { Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue } else { $env:OLLAMA_MODELS = $savedModels }
        if ($null -eq $savedContext) { Remove-Item Env:OLLAMA_CONTEXT_LENGTH -ErrorAction SilentlyContinue } else { $env:OLLAMA_CONTEXT_LENGTH = $savedContext }
        if ($null -eq $savedLibrary) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue } else { $env:OLLAMA_LLM_LIBRARY = $savedLibrary }
    }
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 500
        if ($process.HasExited) { break }
        try { if ((Invoke-WebRequest "http://127.0.0.1:$port/api/version" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { return [pscustomobject]@{ Process = $process; Port = $port } } } catch { }
    }
    if (-not $process.HasExited) { Stop-ProcessTree $process.Id }
    throw "Portable Ollama did not become ready."
}

function Invoke-OllamaCommand([string[]]$Arguments) {
    $runtime = $null
    $ownsServer = $false
    try {
        if (Test-Path -LiteralPath $statePath) {
            try {
                $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
                if ($state.source -eq "ollama" -and $state.port -and $state.server -and ((Resolve-Path -LiteralPath $state.server -ErrorAction Stop).Path -ieq (Resolve-Path -LiteralPath $executable).Path)) {
                    if ((Invoke-WebRequest "http://127.0.0.1:$($state.port)/api/version" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) {
                        $runtime = [pscustomobject]@{ Process = $null; Port = [int]$state.port }
                    }
                }
            } catch { $runtime = $null }
        }
        if (-not $runtime) { $runtime = Start-Server; $ownsServer = $true }

        $savedHost = $env:OLLAMA_HOST
        $savedModels = $env:OLLAMA_MODELS
        $savedContext = $env:OLLAMA_CONTEXT_LENGTH
        $savedLibrary = $env:OLLAMA_LLM_LIBRARY
        try {
            $env:OLLAMA_HOST = "127.0.0.1:$($runtime.Port)"
            $env:OLLAMA_MODELS = $modelsPath
            $env:OLLAMA_CONTEXT_LENGTH = [string]$contextSize
            if ([bool]$settings.use_gpu) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue } else { $env:OLLAMA_LLM_LIBRARY = "cpu" }
            & $executable @Arguments
            $commandExitCode = [int]$LASTEXITCODE
            if ($commandExitCode -ne 0) { throw "Ollama command failed with exit code $commandExitCode." }
        } finally {
            if ($null -eq $savedHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue } else { $env:OLLAMA_HOST = $savedHost }
            if ($null -eq $savedModels) { Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue } else { $env:OLLAMA_MODELS = $savedModels }
            if ($null -eq $savedContext) { Remove-Item Env:OLLAMA_CONTEXT_LENGTH -ErrorAction SilentlyContinue } else { $env:OLLAMA_CONTEXT_LENGTH = $savedContext }
            if ($null -eq $savedLibrary) { Remove-Item Env:OLLAMA_LLM_LIBRARY -ErrorAction SilentlyContinue } else { $env:OLLAMA_LLM_LIBRARY = $savedLibrary }
        }
    } finally {
        if ($ownsServer -and $runtime -and $runtime.Process) { Stop-ProcessTree $runtime.Process.Id }
    }
}

function Invoke-InteractiveManager {
    while ($true) {
        Write-Host ""
        Write-Host "Portable Ollama model manager"
        Write-Host "Models folder: $modelsPath"
        Write-Host "1. List installed models"
        Write-Host "2. Download a model"
        Write-Host "3. Import from a Modelfile"
        Write-Host "4. Exit"

        $choice = (Read-Host "Choose 1-4").Trim()
        if ($choice -eq "4" -or $choice -ieq "exit") { break }

        try {
            if ($choice -eq "1") {
                Invoke-OllamaCommand @("list")
            } elseif ($choice -eq "2") {
                $name = (Read-Host "Model name (for example qwen3:8b)").Trim()
                if ($name) { Invoke-OllamaCommand @("pull", $name) }
            } elseif ($choice -eq "3") {
                $name = (Read-Host "New model name").Trim()
                $file = (Read-Host "Modelfile path").Trim().Trim('"')
                if ($name -and $file) { Invoke-OllamaCommand @("create", $name, "-f", $file) }
            } else {
                Write-Host "Choose one of the numbered options."
            }
        } catch {
            Write-Host "Operation failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

if (-not $Command -or $Command.Count -eq 0) {
    Invoke-InteractiveManager
} else {
    try {
        Invoke-OllamaCommand $Command
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
