[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

$ErrorActionPreference = "SilentlyContinue"
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$statePath = Join-Path $resolvedRoot "data\local-server.json"
if (-not (Test-Path -LiteralPath $statePath)) { exit 0 }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
function Stop-ProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) { Stop-ProcessTree ([int]$child.ProcessId) }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
if ($state.pid -and $state.server) {
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($state.pid)"
    if ($processInfo -and $processInfo.ExecutablePath -and ((Resolve-Path -LiteralPath $processInfo.ExecutablePath).Path -ieq (Resolve-Path -LiteralPath $state.server).Path)) {
        Stop-ProcessTree ([int]$state.pid)
        Write-Host "Stopped local model server (PID $($state.pid))."
    }
}
Remove-Item -LiteralPath $statePath -Force
