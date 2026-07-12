# sync-from-live.ps1 — copy the live Millennium LuaTools plugin back into this repo.
# Use before committing changes you made directly under Steam's plugins folder.
#
#   pwsh -File scripts/sync-from-live.ps1
#   pwsh -File scripts/sync-from-live.ps1 -SteamPath "D:\Steam"
[CmdletBinding()]
param(
    [string]$SteamPath = "C:\Program Files (x86)\Steam"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$live = Join-Path $SteamPath "millennium\plugins\luatools"

if (-not (Test-Path $live)) {
    throw "Live plugin folder not found: $live"
}

$items = @(
    "backend",
    "public",
    "plugin.json",
    ".millennium"
)

foreach ($item in $items) {
    $from = Join-Path $live $item
    $to = Join-Path $repoRoot $item
    if (-not (Test-Path $from)) {
        Write-Warning "Skipping missing live item: $from"
        continue
    }
    if (Test-Path $to) {
        Remove-Item -LiteralPath $to -Recurse -Force
    }
    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force
    Write-Host "Synced $item"
}

Write-Host "Done. Live plugin copied from:"
Write-Host "  $live"
Write-Host "into repo:"
Write-Host "  $repoRoot"
