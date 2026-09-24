[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "SilentlyContinue"
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$statePath = Join-Path $resolvedRoot "data\local-server.json"
$state = $null
if (Test-Path -LiteralPath $statePath) { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json }
function Stop-ProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-ProcessTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Remove-GeneratedModelConfig {
    $configPath = Join-Path $resolvedRoot "data\config.yaml"
    if (-not (Test-Path -LiteralPath $configPath)) { return }
    $lines = @(Get-Content -LiteralPath $configPath)
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^model:\s*$') { $start = $i; break }
    }
    if ($start -lt 0) { return }
    $end = $start + 1
    while ($end -lt $lines.Count -and ($lines[$end] -match '^\s' -or [string]::IsNullOrWhiteSpace($lines[$end]))) { $end++ }
    $modelBlock = ($lines[$start..($end - 1)] -join [Environment]::NewLine)
    if ($modelBlock -notmatch '(?m)^\s+provider:\s+custom\s*$' -or $modelBlock -notmatch '(?m)^\s+base_url:\s+http://127\.0\.0\.1:') { return }
    $before = @(); $after = @()
    if ($start -gt 0) { $before = @($lines[0..($start - 1)]) }
    if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
    Set-Content -LiteralPath $configPath -Value (($before + $after) -join [Environment]::NewLine) -Encoding utf8
}

function Remove-ManagedLocalProvider {
    $configPath = Join-Path $resolvedRoot "data\config.yaml"
    if (-not (Test-Path -LiteralPath $configPath)) { return }
    $lines = @(Get-Content -LiteralPath $configPath)
    $changed = $false
    while ($true) {
        $start = -1
        $end = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*-\s+name:\s+hermes-pocket-(?:ollama|gguf)\s*$') {
                $start = $i
                $end = $i + 1
                while ($end -lt $lines.Count -and (
                        [string]::IsNullOrWhiteSpace($lines[$end]) -or
                        $lines[$end] -match '^\s' -and $lines[$end] -notmatch '^\s*-\s+name:\s')) {
                    $end++
                }
                break
            }
        }
        if ($start -lt 0) { break }
        $before = @(); $after = @()
        if ($start -gt 0) { $before = @($lines[0..($start - 1)]) }
        if ($end -lt $lines.Count) { $after = @($lines[$end..($lines.Count - 1)]) }
        $lines = @($before + $after)
        $changed = $true
    }
    if ($changed) { Set-Content -LiteralPath $configPath -Value ($lines -join [Environment]::NewLine) -Encoding utf8 }
}
if ($state.pid -and $state.server) {
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)"
    if ($processInfo -and $processInfo.ExecutablePath -and ((Resolve-Path -LiteralPath $processInfo.ExecutablePath).Path -ieq (Resolve-Path -LiteralPath $state.server).Path)) {
        Stop-ProcessTree ([int]$state.pid)
        Write-Host "Stopped local model server (PID $($state.pid))."
    }
}
Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
Remove-GeneratedModelConfig
Remove-ManagedLocalProvider
