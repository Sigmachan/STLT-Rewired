# Alias — prefer install/Windows.ps1 (AIO is idempotent; re-run to refresh).
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
# irm|iex leaves $PSScriptRoot empty — never Join-Path until we know it is set.
if ($PSScriptRoot) {
    $local = Join-Path $PSScriptRoot 'Windows.ps1'
    if (Test-Path -LiteralPath $local) {
        & $local @PSBoundParameters
        return
    }
}
$tmp = Join-Path $env:TEMP ('rewired-Windows-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri 'https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Windows.ps1' -OutFile $tmp -UseBasicParsing
    & $tmp @PSBoundParameters
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
