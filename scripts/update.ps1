# Compat shim — prefer: irm https://sigmachan.ru/install.ps1 | iex
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipManager,
    [switch]$SkipMillennium,
    [switch]$SkipOpenSteamTool,
    [switch]$InstallOpenSteamTool,
    [switch]$SkipShortcut,
    [switch]$FromRepo
)
$ErrorActionPreference = 'Stop'
$local = Join-Path $PSScriptRoot '..\install.ps1'
if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    & $local @PSBoundParameters
    return
}
$tmp = Join-Path $env:TEMP ('rewired-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install.ps1' -OutFile $tmp -UseBasicParsing
    & $tmp @PSBoundParameters
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
