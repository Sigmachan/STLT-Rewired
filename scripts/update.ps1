# update.ps1 - update Rewired plugin + Manager from latest GitHub release.
#   pwsh -NoProfile -ExecutionPolicy Bypass -File update.ps1
#   irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/update.ps1 | iex
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
    $url = 'https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/lib/Rewired.Install.psm1'
    $cache = Join-Path $env:TEMP 'Rewired.Install.psm1'
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing
    Import-Module $cache -Force
}

Import-RewiredInstallModule
Invoke-RewiredUpdate @PSBoundParameters
