# Compat shim — prefer: irm …/install/Windows.ps1 | iex
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
$local = Join-Path $PSScriptRoot '..\install\Windows.ps1'
if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    & $local @PSBoundParameters
    return
}
$url = 'https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows.ps1'
iex (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
