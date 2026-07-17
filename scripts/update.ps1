# Compat shim — prefer: irm https://sigmachan.ru/update.ps1 | iex
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
$tmp = Join-Path $env:TEMP ('rewired-Windows-Update-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Windows-Update.ps1' -OutFile $tmp -UseBasicParsing
    & $tmp @PSBoundParameters
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
