# deploy.ps1 - install STLT-Rewired into the live Millennium plugins dir.
# Reversible: backs up the currently-deployed plugin first. Does NOT restart Steam.
#
#   pwsh -File deploy.ps1            # deploy
#   pwsh -File deploy.ps1 -Restore   # roll back to the last backup
[CmdletBinding()]
param([switch]$Restore)

$ErrorActionPreference = "Stop"
$src     = $PSScriptRoot
$plugins = "C:\Program Files (x86)\Steam\millennium\plugins"
$dst     = Join-Path $plugins "luatools"
# IMPORTANT: backups must live OUTSIDE the plugins/ dir. Millennium keys plugins by the
# "name" field in plugin.json, NOT by folder name. A backup copy inside plugins/ would be a
# second folder still declaring name "luatools" -> duplicate-name collision that crashes the
# Steam UI (steamwebhelper) on launch.
$backupRoot = "C:\Program Files (x86)\Steam\millennium\_plugin-backups"
$backup     = Join-Path $backupRoot ("luatools.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

if ($Restore) {
    $last = Get-ChildItem $backupRoot -Directory -Filter "luatools.backup-*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { throw "No luatools.backup-* found in $backupRoot to restore." }
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $last.FullName $dst -Recurse -Force
    Write-Host "Restored $dst from $($last.Name)" -ForegroundColor Green
    Write-Host "Restart Steam to load the restored plugin." -ForegroundColor Yellow
    return
}

# 1) back up the current deployment (if any) -> OUTSIDE plugins/ (see note above)
if (Test-Path $dst) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Write-Host "Backing up current plugin -> $backup"
    Copy-Item $dst $backup -Recurse -Force
    Remove-Item $dst -Recurse -Force
}

# 2) copy only the shipped surface (skip dev/vcs/research). Anything not shipped that also
# declares a plugin.json (or just clutters the live dir) must be excluded here.
New-Item -ItemType Directory -Path $dst -Force | Out-Null
$exclude = @(".git", ".dev", ".omc", "_refs", "scripts", "REWIRED-PLAN.md", ".gitignore", "deploy.ps1", "run_tests.sh")
Get-ChildItem $src -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dst $_.Name) -Recurse -Force
}

Write-Host "Deployed STLT-Rewired -> $dst" -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  1. Fully restart Steam (Steam menu -> Exit, then relaunch)."
Write-Host "  2. In Steam -> Millennium settings, confirm 'luatools' is enabled."
Write-Host "  3. Open the Millennium/CEF console; expect: [LuaTools] rich UI loaded (<n> bytes)"
Write-Host "  4. Open a game page -> the LuaTools button/panels should appear."
Write-Host ""
Write-Host "Roll back any time:  pwsh -File deploy.ps1 -Restore" -ForegroundColor DarkGray
