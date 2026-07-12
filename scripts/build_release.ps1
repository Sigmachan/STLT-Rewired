# build_release.ps1 — production zip for GitHub Releases (STLT-Rewired.zip).
# Run: pwsh -NoProfile -File scripts/build_release.ps1
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "releases"),
    [string]$AssetName = "STLT-Rewired.zip"
)

$ErrorActionPreference = "Stop"
Push-Location $RepoRoot
try {
    $bundleScript = Join-Path $RepoRoot "scripts\build_webkit_bundle.py"
    if (Test-Path $bundleScript) {
        python $bundleScript
    } else {
        throw "Missing scripts/build_webkit_bundle.py"
    }

    $staging = Join-Path $env:TEMP ("stlt-rewired-release-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    $include = @("backend", "public", ".millennium", "plugin.json")
    foreach ($name in $include) {
        $src = Join-Path $RepoRoot $name
        if (-not (Test-Path $src)) { throw "Missing ship artifact: $name" }
        Copy-Item $src (Join-Path $staging $name) -Recurse -Force
    }

    # Never ship machine-local runtime state in release artifacts.
    $dataDir = Join-Path $staging "backend\data"
    if (Test-Path $dataDir) {
        Remove-Item $dataDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $zipPath = Join-Path $OutDir $AssetName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zipPath -Force
    Remove-Item $staging -Recurse -Force

    $bytes = (Get-Item -LiteralPath $zipPath).Length
    Write-Host "Release artifact: $zipPath ($bytes bytes)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Publish:" -ForegroundColor Cyan
    Write-Host "  1. Tag v<plugin.json version> on main"
    Write-Host "  2. gh release create v<version> $zipPath --title `"STLT-Rewired v<version>`""
    Write-Host "  3. In-plugin updater reads backend/update.json -> asset STLT-Rewired.zip"
} finally {
    Pop-Location
}
