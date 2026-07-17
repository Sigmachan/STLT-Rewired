# Compat shim — prefer: irm …/install/Windows-Update.ps1 | iex
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipManager
)
$ErrorActionPreference = 'Stop'
$local = Join-Path $PSScriptRoot '..\install\Windows-Update.ps1'
if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    & $local @PSBoundParameters
    return
}
$url = 'https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows-Update.ps1'
iex (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
