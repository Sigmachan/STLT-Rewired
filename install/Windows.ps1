# install.ps1 → install/Windows.ps1
# Full Windows stack: Millennium (if needed) + Rewired plugin (+ optional OpenSteamTool).
#   irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows.ps1 | iex
#   pwsh -NoProfile -File install/Windows.ps1
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipMillennium,
    [switch]$SkipManager,
    [switch]$SkipOpenSteamTool,
    [switch]$SkipShortcut,
    [switch]$FromRepo
)

$ErrorActionPreference = 'Stop'

function Import-RewiredInstallModule {
    $local = Join-Path $PSScriptRoot 'lib\Rewired.Install.psm1'
    if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
        Import-Module $local -Force
        return
    }
    $branch = 'main'
    $url = "https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/$branch/install/lib/Rewired.Install.psm1"
    $cache = Join-Path $env:TEMP 'Rewired.Install.psm1'
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing
    Import-Module $cache -Force
}

Import-RewiredInstallModule
Invoke-RewiredInstall @PSBoundParameters
