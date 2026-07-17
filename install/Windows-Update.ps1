# Windows-Update.ps1 — update Rewired plugin from latest GitHub release.
#   irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows-Update.ps1 | iex
#   pwsh -NoProfile -File install/Windows-Update.ps1
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipManager
)

$ErrorActionPreference = 'Stop'

function Import-RewiredInstallModule {
    $local = Join-Path $PSScriptRoot 'lib\Rewired.Install.psm1'
    if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
        Import-Module $local -Force
        return
    }
    $url = 'https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/lib/Rewired.Install.psm1'
    $cache = Join-Path $env:TEMP 'Rewired.Install.psm1'
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing
    Import-Module $cache -Force
}

Import-RewiredInstallModule
Invoke-RewiredUpdate @PSBoundParameters
