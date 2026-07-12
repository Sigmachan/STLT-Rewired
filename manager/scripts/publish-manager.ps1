# publish-manager.ps1 — build Rewired Manager zip for GitHub Releases (STLT-Rewired repo).
# Run: pwsh -NoProfile -File manager/scripts/publish-manager.ps1
[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [string]$Version = "",
    [string]$DotNet = ""
)

$ErrorActionPreference = "Stop"
$managerRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $managerRoot -Parent
$project = Join-Path $managerRoot "RewiredManager.App\RewiredManager.App.csproj"
$artifacts = Join-Path $managerRoot "artifacts"
$publishDir = Join-Path $artifacts "release"
$releasesDir = Join-Path $repoRoot "releases"
$zipName = "RewiredManager-$Runtime-framework-dependent.zip"
$zipPath = Join-Path $releasesDir $zipName

function Resolve-DotNet {
    param([string]$Override)
    if ($Override -and (Test-Path -LiteralPath $Override)) { return $Override }
    $candidates = @(
        $env:DOTNET_ROOT,
        "F:\dotnet-sdk\dotnet.exe",
        (Join-Path $env:ProgramFiles "dotnet\dotnet.exe")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $onPath = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw "No .NET SDK found. Install .NET 8 SDK or set -DotNet to dotnet.exe path."
}

$dotnet = Resolve-DotNet -Override $DotNet
Remove-Item -LiteralPath $publishDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $publishDir, $releasesDir | Out-Null

& $dotnet publish $project -c $Configuration -r $Runtime --self-contained false -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }

Get-ChildItem -LiteralPath $publishDir -Filter "*.pdb" -File -ErrorAction SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $zipPath -Force

$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
$shaFile = Join-Path $releasesDir "SHA256SUMS.txt"
$line = "$sha  $zipName"
if (Test-Path $shaFile) {
    $existing = Get-Content $shaFile | Where-Object { $_ -notmatch [regex]::Escape($zipName) }
    ($existing + $line) | Set-Content $shaFile -Encoding ASCII
} else {
    Set-Content $shaFile -Value $line -Encoding ASCII
}

Write-Host "Published $zipPath" -ForegroundColor Green
Write-Host "SHA256 $sha"
Write-Host ""
Write-Host "Attach to GitHub release alongside STLT-Rewired.zip:" -ForegroundColor Cyan
if ($Version) {
    Write-Host "  gh release upload v$Version $zipPath --clobber"
} else {
    Write-Host "  gh release upload v<version> $zipPath --clobber"
}
