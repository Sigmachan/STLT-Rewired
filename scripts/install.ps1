# Compat shim — prefer: irm https://sigmachan.ru/install.ps1 | iex
[CmdletBinding()]
param(
    [string]$SteamPath = '',
    [switch]$SkipMillennium,
    [switch]$SkipManager,
    [switch]$SkipOpenSteamTool,
    [switch]$InstallOpenSteamTool,
    [switch]$SkipShortcut,
    [switch]$FromRepo
)
$ErrorActionPreference = 'Stop'
$local = Join-Path $PSScriptRoot '..\install\Windows.ps1'
if ($PSScriptRoot -and (Test-Path -LiteralPath $local)) {
    & $local @PSBoundParameters
    return
}
$tmp = Join-Path $env:TEMP ('rewired-Windows-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Windows.ps1' -OutFile $tmp -UseBasicParsing
    & $tmp @PSBoundParameters
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
