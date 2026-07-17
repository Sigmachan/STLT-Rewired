# Short Windows update entrypoint.
#   irm https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/u.ps1 | iex
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipManager
)
$ErrorActionPreference = 'Stop'
$local = Join-Path $PSScriptRoot 'install\Windows-Update.ps1'
if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    & $local @PSBoundParameters
    return
}
iex (Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Windows-Update.ps1' -UseBasicParsing).Content
