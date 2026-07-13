# smoke_deploy.ps1 — post-deploy sanity checks for STLT-Rewired (Phase 1 verify).
# Does not require Steam to be running; validates the live plugin tree on disk.
# Run: pwsh -NoProfile -File scripts/smoke_deploy.ps1
[CmdletBinding()]
param(
    [string]$SteamPath = "C:\Program Files (x86)\Steam",
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"
$dst = Join-Path $SteamPath "millennium\plugins\luatools"
$failures = @()
$warnings = @()

function Pass([string]$msg) { Write-Host "  OK  $msg" -ForegroundColor Green }
function Warn([string]$msg) { $script:warnings += $msg; Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Fail([string]$msg) { $script:failures += $msg; Write-Host "  FAIL $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "STLT-Rewired deploy smoke test" -ForegroundColor Cyan
Write-Host "Live plugin: $dst" -ForegroundColor DarkGray
Write-Host ""

# --- structure ---
Write-Host "[structure]" -ForegroundColor Cyan
$required = @(
    "plugin.json",
    ".millennium\Dist\webkit.js",
    "public\luatools.js",
    "backend\main.lua",
    "backend\manifesthub.lua",
    "backend\manifests.lua",
    "backend\manifest_auto_updater.lua",
    "backend\github_mirror.lua",
    "backend\unlock_paths.lua",
    "backend\health.lua",
    "backend\setup_assistant.lua",
    "backend\ryuu.lua"
)
foreach ($rel in $required) {
    $p = Join-Path $dst $rel
    if (Test-Path -LiteralPath $p) { Pass $rel } else { Fail "Missing $rel" }
}

# --- plugin.json ---
Write-Host "[plugin.json]" -ForegroundColor Cyan
$pjPath = Join-Path $dst "plugin.json"
try {
    $pj = Get-Content -Raw -LiteralPath $pjPath | ConvertFrom-Json
    if ($pj.name -eq "luatools") { Pass "name=luatools" } else { Fail "plugin.json name is '$($pj.name)', expected luatools" }
    if ($pj.backendType -eq "lua") { Pass "backendType=lua" } else { Fail "backendType is '$($pj.backendType)'" }
    if ($pj.useBackend -eq $true) { Pass "useBackend=true" } else { Fail "useBackend is not true" }
    Pass "version=$($pj.version)"
} catch {
    Fail "plugin.json parse error: $_"
}

# --- duplicate plugin folders ---
Write-Host "[duplicate plugins]" -ForegroundColor Cyan
$pluginName = "luatools"
$dupes = @()
foreach ($root in @(
    (Join-Path $SteamPath "millennium\plugins"),
    (Join-Path $SteamPath "plugins")
)) {
    if (-not (Test-Path $root)) { continue }
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path $d.FullName "plugin.json"
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        try {
            $n = (Get-Content -Raw -LiteralPath $candidate | ConvertFrom-Json).name
            if ($n -eq $pluginName) { $dupes += $d.FullName }
        } catch { }
    }
}
$dupes = @($dupes | Select-Object -Unique)
if ($dupes.Count -le 1) {
    Pass "single luatools plugin folder ($($dupes.Count) found)"
} else {
    Fail "$($dupes.Count) luatools plugin folders: $($dupes -join '; ')"
}

# --- webkit bundle markers ---
Write-Host "[webkit.js markers]" -ForegroundColor Cyan
$webkit = Join-Path $dst ".millennium\Dist\webkit.js"
if (Test-Path -LiteralPath $webkit) {
    $bytes = (Get-Item -LiteralPath $webkit).Length
    if ($bytes -gt 100000) { Pass "webkit.js size ${bytes} bytes" } else { Fail "webkit.js suspiciously small ($bytes bytes)" }
    $content = Get-Content -Raw -LiteralPath $webkit
    foreach ($needle in @(
        "ValidateManifestHubKey",
        "WarmRyuuCatalogCache",
        "RunManifestAutoUpdate",
        "GetSetupState",
        "Test ManifestHub key",
        "Remove via Rewired",
        "Rewired \u00b7 Menu"
    )) {
        if ($content -match [regex]::Escape($needle)) { Pass "contains '$needle'" } else { Fail "webkit.js missing '$needle'" }
    }
}

# --- locale branding (runtime strings) ---
Write-Host "[locale branding]" -ForegroundColor Cyan
$enLocale = Join-Path $dst "backend\locales\en.json"
if (Test-Path -LiteralPath $enLocale) {
    $en = Get-Content -Raw -LiteralPath $enLocale
    if ($en -match 'Add via Rewired') { Pass "en.json Add via Rewired" } else { Fail "en.json missing Add via Rewired" }
    if ($en -match '"common\.appName": "Rewired"') { Pass "en.json common.appName=Rewired" } else { Fail "en.json common.appName not Rewired" }
}

# --- backend RPC markers ---
Write-Host "[backend RPC markers]" -ForegroundColor Cyan
$mainLua = Join-Path $dst "backend\main.lua"
if (Test-Path -LiteralPath $mainLua) {
    $lua = Get-Content -Raw -LiteralPath $mainLua
    foreach ($fn in @(
        "function ValidateManifestHubKey",
        "function ValidateMorrenusKey",
        "function WarmRyuuCatalogCache",
        "function RunManifestAutoUpdate",
        "function GetSetupState",
        "function GetUnlockBackendStatus",
        "function GetUpdateStatus",
        "function SelfHeal",
        "require\(""unlock_paths""\)",
        "require\(""manifesthub""\)"
    )) {
        if ($lua -match $fn) { Pass "main.lua has $fn" } else { Fail "main.lua missing $fn" }
    }
    if ($lua -match 'local manifest_auto\s*=\s*require\("manifest_auto_updater"\)[\s\S]*local manifest_auto\s*=\s*require\("manifest_auto_updater"\)') {
        Fail "main.lua has duplicate manifest_auto require"
    } else {
        Pass "no duplicate manifest_auto require"
    }
    if ($lua -match 'fx\.for\s*=') {
        Fail "main.lua or health.lua may still use reserved word fx.for"
    } else {
        Pass "no fx.for reserved-word pattern in main.lua"
    }
}

$healthLua = Join-Path $dst "backend\health.lua"
if (Test-Path -LiteralPath $healthLua) {
    $h = Get-Content -Raw -LiteralPath $healthLua
    if ($h -match 'fx\.for\s*=') { Fail "health.lua still uses fx.for (Lua reserved word)" }
    else { Pass "health.lua avoids fx.for" }
}

# --- repo vs live version parity (informational) ---
Write-Host "[repo parity]" -ForegroundColor Cyan
$repoWebkit = Join-Path $RepoRoot ".millennium\Dist\webkit.js"
$liveWebkit = Join-Path $dst ".millennium\Dist\webkit.js"
if ((Test-Path $repoWebkit) -and (Test-Path $liveWebkit)) {
    $repoHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $repoWebkit).Hash
    $liveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveWebkit).Hash
    if ($repoHash -eq $liveHash) { Pass "live webkit.js matches repo build" }
    else { Warn "live webkit.js differs from repo (redeploy or rebuild?)" }
}

# --- Steam process state ---
Write-Host "[runtime]" -ForegroundColor Cyan
$steam = Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue
if ($steam) {
    Warn "Steam is running — restart fully to load the new plugin (Exit Steam, relaunch)"
} else {
    Pass "Steam not running (good time to start fresh after deploy)"
}

# --- summary ---
Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "Smoke test PASSED ($($warnings.Count) warning(s))" -ForegroundColor Green
} else {
    Write-Host "Smoke test FAILED: $($failures.Count) issue(s), $($warnings.Count) warning(s)" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
}
if ($warnings.Count -gt 0) {
    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
}
Write-Host ""
Write-Host "Manual UI checklist (after Steam restart):" -ForegroundColor Cyan
Write-Host "  1. CEF console: [LuaTools] rich UI loaded"
Write-Host "  2. Game page: Add via Rewired button appears"
Write-Host "  3. Menu title: Rewired · Menu"
Write-Host "  4. Settings -> Test ManifestHub key"
Write-Host "  5. Ryuu catalog opens and search works (first open may cache ~1 min)"
Write-Host ""

if ($failures.Count -gt 0) { exit 1 }
exit 0
