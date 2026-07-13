# publish_release.ps1 - build zips and create GitHub release (requires gh CLI + auth).
# Run: pwsh -NoProfile -File scripts/publish_release.ps1 -Version 0.1.5
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [string]$Tag = "",
    [switch]$SkipBuild,
    [switch]$Draft
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $Tag) { $Tag = "v$Version" }

if (-not $SkipBuild) {
    & pwsh -NoProfile -File (Join-Path $repoRoot "scripts\build_release.ps1")
    & pwsh -NoProfile -File (Join-Path $repoRoot "manager\scripts\publish-manager.ps1")
}

$pluginZip = Join-Path $repoRoot "releases\STLT-Rewired.zip"
$managerZip = Join-Path $repoRoot "releases\RewiredManager-win-x64-framework-dependent.zip"
foreach ($f in @($pluginZip, $managerZip)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Missing release asset: $f" }
}

$draftFlag = if ($Draft) { "--draft" } else { "" }
$notes = @"
STLT-Rewired $Version

Windows one-liner install:
  irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.ps1 | iex

Windows update:
  irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/update.ps1 | iex

Linux install:
  curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh | bash
"@

$bodyFile = Join-Path $env:TEMP ("rewired-release-notes-" + [guid]::NewGuid().ToString("N") + ".md")
Set-Content -Path $bodyFile -Value $notes -Encoding UTF8

try {
    if ($Draft) {
        gh release create $Tag $pluginZip $managerZip --title "STLT-Rewired $Version" --notes-file $bodyFile --draft
    } else {
        gh release create $Tag $pluginZip $managerZip --title "STLT-Rewired $Version" --notes-file $bodyFile
    }
    Write-Host "Release $Tag published." -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
}
