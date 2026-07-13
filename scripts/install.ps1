# install.ps1 - one-shot Rewired install (Windows).
#   pwsh -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.ps1 | iex
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipMillennium,
    [switch]$SkipManager,
    [switch]$SkipOpenSteamTool,
    [switch]$SkipShortcut
)

$ErrorActionPreference = 'Stop'

function Import-RewiredInstallModule {
    $local = Join-Path $PSScriptRoot 'lib\Rewired.Install.psm1'
    if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
        Import-Module $local -Force
        return
    }
    $branch = 'main'
    $url = "https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/$branch/scripts/lib/Rewired.Install.psm1"
    $cache = Join-Path $env:TEMP 'Rewired.Install.psm1'
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing
    Import-Module $cache -Force
}

Import-RewiredInstallModule
Invoke-RewiredInstall @PSBoundParameters
