# install.ps1 → install/Windows.ps1
# Full Windows AIO: Millennium (if needed) + OpenSteamTool + Rewired plugin.
#   irm https://sigmachan.ru/install.ps1 | iex
#   pwsh -NoProfile -File install/Windows.ps1
#   pwsh -NoProfile -File install/Windows.ps1 -SkipOpenSteamTool
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

function Import-RewiredInstallModule {
    # When this file is run from disk, prefer sibling module; irm|iex / empty root → CDN.
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'lib\Rewired.Install.psm1'
        if (Test-Path -LiteralPath $local) {
            Import-Module $local -Force
            return $null
        }
    }
    $branch = 'main'
    $url = "https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@$branch/install/lib/Rewired.Install.psm1"
    $cache = Join-Path $env:TEMP ('Rewired.Install-' + [guid]::NewGuid().ToString('N') + '.psm1')
    Invoke-WebRequest -Uri $url -OutFile $cache -UseBasicParsing
    Import-Module $cache -Force
    return $cache
}

$script:RewiredInstallModuleCache = Import-RewiredInstallModule
try {
    # Strip legacy/no-op switches that Invoke-RewiredInstall does not declare.
    $installParams = @{}
    foreach ($key in @('SteamPath', 'SkipMillennium', 'SkipOpenSteamTool', 'InstallOpenSteamTool', 'SkipShortcut', 'FromRepo')) {
        if ($PSBoundParameters.ContainsKey($key)) { $installParams[$key] = $PSBoundParameters[$key] }
    }
    Invoke-RewiredInstall @installParams
} finally {
    if ($script:RewiredInstallModuleCache) {
        Remove-Item -LiteralPath $script:RewiredInstallModuleCache -Force -ErrorAction SilentlyContinue
    }
}
