[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [switch]$KeepData
)

$ErrorActionPreference = "Stop"
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$targets = @(
    (Join-Path $resolvedRoot ".cache"),
    (Join-Path $resolvedRoot ".tmp"),
    (Join-Path $resolvedRoot "src")
)
if (-not $KeepData) { $targets += Join-Path $resolvedRoot "data" }

foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) {
        if ($PSCmdlet.ShouldProcess($target, "Remove portable Hermes state")) {
            Remove-Item -LiteralPath $target -Recurse -Force
            Write-Host "Removed $target"
        }
    }
}
Write-Host "Reset complete. Run launch.bat to set up again."
