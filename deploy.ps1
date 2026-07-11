# deploy.ps1 - install STLT-Rewired into the live Millennium plugins dir.
# Reversible: backs up the currently-deployed plugin first. Does NOT restart Steam.
#
#   pwsh -File deploy.ps1                                    # deploy LuaTools/STLT only
#   pwsh -File deploy.ps1 -InstallMillenniumBeta             # update Millennium beta, then deploy
#   pwsh -File deploy.ps1 -Restore                           # roll back to the last plugin backup
[CmdletBinding()]
param(
    [switch]$Restore,
    [switch]$InstallMillenniumBeta,
    [string]$MillenniumVersion = "v3.4.0-beta.8",
    [string]$SteamPath = "C:\Program Files (x86)\Steam"
)

$ErrorActionPreference = "Stop"
$src     = $PSScriptRoot
$plugins = Join-Path $SteamPath "millennium\plugins"
$dst     = Join-Path $plugins "luatools"
# IMPORTANT: backups must live OUTSIDE the plugins/ dir. Millennium keys plugins by the
# "name" field in plugin.json, NOT by folder name. A backup copy inside plugins/ would be a
# second folder still declaring name "luatools" -> duplicate-name collision that crashes the
# Steam UI (steamwebhelper) on launch.
$backupRoot = Join-Path $SteamPath "millennium\_plugin-backups"
$backup     = Join-Path $backupRoot ("luatools.backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

function Get-TempRoot {
    $tempRoot = $env:TEMP
    if (-not $tempRoot) { $tempRoot = [System.IO.Path]::GetTempPath() }
    return $tempRoot
}

function New-TempWorkspace {
    param([Parameter(Mandatory=$true)][string]$Prefix)
    $path = Join-Path (Get-TempRoot) ($Prefix + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Assert-SteamStopped {
    $running = Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue
    if ($running) {
        $names = ($running | Select-Object -ExpandProperty ProcessName -Unique) -join ", "
        throw "Steam is still running ($names). Exit Steam fully before installing Millennium runtime."
    }
}

function Restore-MillenniumRuntimeBackup {
    param(
        [Parameter(Mandatory=$true)][string]$SteamRoot,
        [Parameter(Mandatory=$true)][string]$BackupPath
    )

    $millenniumRoot = Join-Path $SteamRoot "millennium"
    $loaderBackup = Join-Path $BackupPath "wsock32.dll"
    if (Test-Path $loaderBackup) {
        Copy-Item $loaderBackup (Join-Path $SteamRoot "wsock32.dll") -Force
    }

    foreach ($dir in @("bin", "lib")) {
        $target = Join-Path $millenniumRoot $dir
        $backupDir = Join-Path (Join-Path $BackupPath "millennium") $dir
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        if (Test-Path $backupDir) { Copy-Item $backupDir $target -Recurse -Force }
    }
}

function Install-MillenniumBeta {
    param(
        [Parameter(Mandatory=$true)][string]$Version,
        [Parameter(Mandatory=$true)][string]$SteamRoot
    )

    if (-not (Test-Path $SteamRoot)) { throw "Steam path not found: $SteamRoot" }
    Assert-SteamStopped

    $assetBase = "millennium-$Version-windows-x86_64"
    $releaseBase = "https://github.com/SteamClientHomebrew/Millennium/releases/download/$Version"
    $zipUrl = "$releaseBase/$assetBase.zip"
    $shaUrl = "$releaseBase/$assetBase.sha256"
    $work = New-TempWorkspace -Prefix "millennium-update-"

    try {
        $zipPath = Join-Path $work "$assetBase.zip"
        $shaPath = Join-Path $work "$assetBase.sha256"
        Write-Host "Downloading Millennium $Version..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath
        Invoke-WebRequest -Uri $shaUrl -OutFile $shaPath

        $expected = ((Get-Content $shaPath -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
        $actual = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLowerInvariant()
        if ($expected -ne $actual) { throw "Millennium archive SHA256 mismatch. expected=$expected actual=$actual" }

        $millenniumRoot = Join-Path $SteamRoot "millennium"
        $runtimeBackupRoot = Join-Path $millenniumRoot "_millennium-backups"
        $runtimeBackup = Join-Path $runtimeBackupRoot ("millennium-runtime-before-$Version-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        New-Item -ItemType Directory -Path $runtimeBackup -Force | Out-Null

        $loader = Join-Path $SteamRoot "wsock32.dll"
        if (Test-Path $loader) { Copy-Item $loader (Join-Path $runtimeBackup "wsock32.dll") -Force }
        foreach ($dir in @("bin", "lib")) {
            $from = Join-Path $millenniumRoot $dir
            if (Test-Path $from) {
                $backupMillennium = Join-Path $runtimeBackup "millennium"
                New-Item -ItemType Directory -Path $backupMillennium -Force | Out-Null
                Copy-Item $from (Join-Path $backupMillennium $dir) -Recurse -Force
            }
        }

        $extract = Join-Path $work "extract"
        Expand-Archive -Path $zipPath -DestinationPath $extract -Force

        $newLoader = Join-Path $extract "wsock32.dll"
        $newBin = Join-Path $extract "millennium\bin"
        $newLib = Join-Path $extract "millennium\lib"
        foreach ($required in @($newLoader, $newBin, $newLib)) {
            if (-not (Test-Path $required)) { throw "Millennium archive missing expected path: $required" }
        }

        try {
            Copy-Item $newLoader $loader -Force
            foreach ($dir in @("bin", "lib")) {
                $target = Join-Path $millenniumRoot $dir
                if (Test-Path $target) { Remove-Item $target -Recurse -Force }
            }
            New-Item -ItemType Directory -Path $millenniumRoot -Force | Out-Null
            Copy-Item $newBin (Join-Path $millenniumRoot "bin") -Recurse -Force
            Copy-Item $newLib (Join-Path $millenniumRoot "lib") -Recurse -Force
        }
        catch {
            Write-Host "Millennium runtime update failed; restoring backup..." -ForegroundColor Yellow
            Restore-MillenniumRuntimeBackup -SteamRoot $SteamRoot -BackupPath $runtimeBackup
            throw
        }

        Write-Host "Installed Millennium $Version runtime -> $SteamRoot" -ForegroundColor Green
        Write-Host "Millennium rollback backup -> $runtimeBackup" -ForegroundColor DarkGray
    }
    finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($Restore) {
    $last = Get-ChildItem $backupRoot -Directory -Filter "luatools.backup-*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    if (-not $last) { throw "No luatools.backup-* found in $backupRoot to restore." }
    New-Item -ItemType Directory -Path $plugins -Force | Out-Null
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $last.FullName $dst -Recurse -Force
    Write-Host "Restored $dst from $($last.Name)" -ForegroundColor Green
    Write-Host "Restart Steam to load the restored plugin." -ForegroundColor Yellow
    return
}

if ($InstallMillenniumBeta) {
    Install-MillenniumBeta -Version $MillenniumVersion -SteamRoot $SteamPath
}

# Keep the shipped webkit module in sync with public\luatools.js. Millennium 3.4 loads
# .millennium\Dist\webkit.js directly; using add_browser_js for store pages is CSP-blocked.
$bundleScript = Join-Path $src "scripts\build_webkit_bundle.py"
if (Test-Path $bundleScript) {
    python $bundleScript
    if ($LASTEXITCODE -ne 0) { throw "Failed to rebuild .millennium\Dist\webkit.js" }
}

# 1) back up the current deployment (if any) -> OUTSIDE plugins/ (see note above)
$preservedData = $null
if (Test-Path $dst) {
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Write-Host "Backing up current plugin -> $backup"
    Copy-Item $dst $backup -Recurse -Force

    # Keep machine-local runtime state across deploys. The backup is still complete,
    # but deleting $dst would otherwise wipe settings/secrets before the new tree is copied.
    $liveData = Join-Path $dst "backend\data"
    if (Test-Path $liveData) {
        $preservedData = Join-Path (Get-TempRoot) ("luatools-data-" + [guid]::NewGuid().ToString("N"))
        Copy-Item $liveData $preservedData -Recurse -Force
    }

    Remove-Item $dst -Recurse -Force
}

# 2) copy only the shipped runtime surface. Anything outside this allowlist is dev/VCS/local
# state and must not land in Steam's live plugin directory.
New-Item -ItemType Directory -Path $dst -Force | Out-Null
$include = @("backend", "public", ".millennium", "plugin.json")
foreach ($name in $include) {
    $item = Join-Path $src $name
    if (Test-Path $item) {
        Copy-Item $item (Join-Path $dst $name) -Recurse -Force
    }
}

if ($preservedData -and (Test-Path $preservedData)) {
    $newData = Join-Path $dst "backend\data"
    New-Item -ItemType Directory -Path $newData -Force | Out-Null
    Copy-Item (Join-Path $preservedData "*") $newData -Recurse -Force
    Remove-Item $preservedData -Recurse -Force
    Write-Host "Preserved backend\data from the previous deployment" -ForegroundColor DarkGray
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
