# Rewired release/install helpers (Windows). Dot-source or Import-Module from install.ps1 / update.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RewiredGitHubOwner = 'Sigmachan'
$script:RewiredGitHubRepo  = 'STLT-Rewired'
$script:RewiredPluginAsset = 'STLT-Rewired.zip'
$script:RewiredTagPrefix = 'v'

function Get-RewiredConfigDir {
    Join-Path $env:LOCALAPPDATA 'Rewired'
}

function Get-SteamInstallPath {
    param([string]$Override = '')
    if ($Override -and (Test-Path -LiteralPath $Override)) {
        return (Resolve-Path -LiteralPath $Override).Path
    }
    foreach ($view in @([Microsoft.Win32.RegistryView]::Default, [Microsoft.Win32.RegistryView]::Registry32)) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, $view)
            $key = $base.OpenSubKey('Software\Valve\Steam')
            if ($key) {
                $p = $key.GetValue('SteamPath')
                if ($p -and (Test-Path -LiteralPath $p)) { return $p.ToString().TrimEnd('\') }
            }
        } catch { }
    }
    $fallback = Join-Path ${env:ProgramFiles(x86)} 'Steam'
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    throw 'Steam installation not found. Pass -SteamPath.'
}

function Get-GitHubAuthToken {
    if ($env:GITHUB_TOKEN) { return [string]$env:GITHUB_TOKEN }
    if ($env:GH_TOKEN) { return [string]$env:GH_TOKEN }
    return $null
}

function Get-GitHubApiHeaders {
    $headers = @{
        Accept       = 'application/vnd.github+json'
        'User-Agent' = 'Rewired-Installer'
    }
    $token = Get-GitHubAuthToken
    if ($token) { $headers.Authorization = "Bearer $token" }
    return $headers
}

function Test-GitHubRateLimitError {
    param($ErrorRecord)
    $detail = ''
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $detail = [string]$ErrorRecord.ErrorDetails.Message
    }
    if ($detail -match 'rate limit') { return $true }
    try {
        $code = [int]$ErrorRecord.Exception.Response.StatusCode
        if ($code -eq 403 -or $code -eq 429) { return $true }
    } catch { }
    return $false
}

function Get-GitHubLatestTagFromRedirect {
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo
    )
    $uri = "https://github.com/$Owner/$Repo/releases/latest"
    try {
        $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
        $final = $resp.BaseResponse.ResponseUri.AbsoluteUri
        if ($final -match '/tag/([^/?#]+)') { return $Matches[1] }
        if ($resp.Content -match 'releases/tag/([^"''\s/?#]+)') { return $Matches[1] }
    } catch { }
    return 'latest'
}

function Get-RewiredReleaseDirectUrls {
    param([string]$Tag = 'latest')
    $base = "https://github.com/$($script:RewiredGitHubOwner)/$($script:RewiredGitHubRepo)/releases/latest/download"
    $version = $Tag
    if ($script:RewiredTagPrefix -and $version.StartsWith($script:RewiredTagPrefix)) {
        $version = $version.Substring($script:RewiredTagPrefix.Length)
    }
    [pscustomobject]@{
        Tag        = $Tag
        Version    = $version
        PluginUrl  = "$base/$($script:RewiredPluginAsset)"
        HtmlUrl    = "https://github.com/$($script:RewiredGitHubOwner)/$($script:RewiredGitHubRepo)/releases/latest"
    }
}

function Get-RewiredLatestRelease {
    $uri = "https://api.github.com/repos/$($script:RewiredGitHubOwner)/$($script:RewiredGitHubRepo)/releases/latest"
    try {
        $json = Invoke-RestMethod -Uri $uri -Headers (Get-GitHubApiHeaders) -TimeoutSec 60
        $version = [string]$json.tag_name
        if ($script:RewiredTagPrefix -and $version.StartsWith($script:RewiredTagPrefix)) {
            $version = $version.Substring($script:RewiredTagPrefix.Length)
        }
        $pluginUrl = $null
        foreach ($asset in $json.assets) {
            if ($asset.name -eq $script:RewiredPluginAsset) { $pluginUrl = $asset.browser_download_url }
        }
        if (-not $pluginUrl) { throw "Release $($json.tag_name) has no asset $($script:RewiredPluginAsset)." }
        return [pscustomobject]@{
            Tag        = $json.tag_name
            Version    = $version
            PluginUrl  = $pluginUrl
            HtmlUrl    = $json.html_url
        }
    } catch {
        if (-not (Test-GitHubRateLimitError $_)) { throw }
        Write-Warning 'GitHub API rate limit reached; using direct release download URLs instead.'
        Write-Warning 'Tip: set GITHUB_TOKEN (or GH_TOKEN) for a higher API limit on future runs.'
        $tag = Get-GitHubLatestTagFromRedirect -Owner $script:RewiredGitHubOwner -Repo $script:RewiredGitHubRepo
        return Get-RewiredReleaseDirectUrls -Tag $tag
    }
}

function Get-OpenSteamToolReleaseZipUrl {
    $uri = 'https://api.github.com/repos/OpenSteam001/OpenSteamTool/releases/latest'
    try {
        $rel = Invoke-RestMethod -Uri $uri -Headers (Get-GitHubApiHeaders) -TimeoutSec 60
        $asset = $rel.assets | Where-Object { $_.name -match 'Release\.zip$' -and $_.name -notmatch 'Debug' } | Select-Object -First 1
        if ($asset) { return [string]$asset.browser_download_url }
        throw 'OpenSteamTool Release zip not found in API response.'
    } catch {
        if (-not (Test-GitHubRateLimitError $_)) { throw }
        Write-Warning 'GitHub API rate limit reached; resolving OpenSteamTool zip from releases page.'
        $page = Invoke-WebRequest -Uri 'https://github.com/OpenSteam001/OpenSteamTool/releases/latest' -UseBasicParsing -TimeoutSec 60
        if ($page.Content -match '/OpenSteam001/OpenSteamTool/releases/download/[^"''\s]+/OpenSteamTool-[^"''\s]+-Release\.zip') {
            return 'https://github.com' + $Matches[0]
        }
        throw 'OpenSteamTool Release zip not found. Install later from Rewired Manager or retry with GITHUB_TOKEN set.'
    }
}

function Compare-RewiredVersion {
    param([string]$Latest, [string]$Current)
    function Parse([string]$v) {
        $nums = @()
        foreach ($p in (($v -replace '^v', '') -split '\.')) {
            if ($p -match '^(\d+)') { $nums += [int]$Matches[1] } else { $nums += 0 }
        }
        while ($nums.Count -lt 3) { $nums += 0 }
        ,@($nums[0], $nums[1], $nums[2])
    }
    $a = Parse $Latest
    $b = Parse $Current
    for ($i = 0; $i -lt 3; $i++) {
        if ($a[$i] -gt $b[$i]) { return 1 }
        if ($a[$i] -lt $b[$i]) { return -1 }
    }
    0
}

function Save-RewiredSharedConfig {
    param(
        [string]$SteamPath,
        [string]$PluginPath,
        [string]$UnlockBackend = 'auto'
    )
    $dir = Get-RewiredConfigDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $cfg = @{
        version            = 1
        steamPath          = $SteamPath
        unlockBackend      = $UnlockBackend
        millenniumOptional = $true
        pluginPath         = $PluginPath
        repoRoot           = ''
    }
    $path = Join-Path $dir 'rewired.json'
    $cfg | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
    return $path
}

function Get-RewiredLocalRepoRoot {
    $scriptsDir = Split-Path $PSScriptRoot -Parent
    $root = Split-Path $scriptsDir -Parent
    if (Test-Path -LiteralPath (Join-Path $root 'deploy.ps1')) { return $root }
    return $null
}

function Install-RewiredPluginFromLocalRepo {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$SteamPath
    )
    $deploy = Join-Path $RepoRoot 'deploy.ps1'
    if (-not (Test-Path -LiteralPath $deploy)) {
        throw "deploy.ps1 not found at $deploy"
    }
    & pwsh -NoProfile -File $deploy -SteamPath $SteamPath
    if ($LASTEXITCODE -ne 0) { throw "deploy.ps1 failed with exit code $LASTEXITCODE" }
    return Join-Path $SteamPath 'millennium\plugins\luatools'
}

function Install-RewiredPluginFromUrl {
    param(
        [Parameter(Mandatory)][string]$ZipUrl,
        [Parameter(Mandatory)][string]$SteamPath
    )
    $pluginRoot = Join-Path $SteamPath 'millennium\plugins\luatools'
    $backupRoot = Join-Path $SteamPath 'millennium\_plugin-backups'
    $work = Join-Path $env:TEMP ('rewired-plugin-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work 'plugin.zip'
    $extract = Join-Path $work 'extract'
    New-Item -ItemType Directory -Force -Path $work, $extract | Out-Null

    try {
        try {
            Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
        } catch {
            $notFound = $false
            try { $notFound = [int]$_.Exception.Response.StatusCode -eq 404 } catch { }
            if ($notFound) {
                throw "Plugin zip not found at $ZipUrl. Publish a GitHub release (scripts/publish_release.ps1) or run install.ps1 -FromRepo from a git checkout."
            }
            throw
        }
        Expand-Archive -Path $zipPath -DestinationPath $extract -Force

        $preservedData = $null
        if (Test-Path -LiteralPath $pluginRoot) {
            New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
            $backup = Join-Path $backupRoot ('luatools.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $pluginRoot -Destination $backup -Recurse -Force
            $liveData = Join-Path $pluginRoot 'backend\data'
            if (Test-Path -LiteralPath $liveData) {
                $preservedData = Join-Path $work 'preserved-data'
                Copy-Item -LiteralPath $liveData -Destination $preservedData -Recurse -Force
            }
            Remove-Item -LiteralPath $pluginRoot -Recurse -Force
        }

        New-Item -ItemType Directory -Force -Path (Split-Path $pluginRoot -Parent) | Out-Null
        Copy-Item -Path (Join-Path $extract '*') -Destination $pluginRoot -Recurse -Force

        if ($preservedData -and (Test-Path -LiteralPath $preservedData)) {
            $newData = Join-Path $pluginRoot 'backend\data'
            New-Item -ItemType Directory -Force -Path $newData | Out-Null
            Copy-Item -Path (Join-Path $preservedData '*') -Destination $newData -Recurse -Force
        }

        return $pluginRoot
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RewiredMillennium {
    param(
        [Parameter(Mandatory)][string]$SteamPath,
        [string]$Version = 'v3.4.0-beta.8'
    )
    $running = Get-Process -Name 'steam', 'steamwebhelper' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Warning 'Steam is running. Exit Steam fully before installing Millennium.'
        return $false
    }
    $assetBase = "millennium-$Version-windows-x86_64"
    $base = "https://github.com/SteamClientHomebrew/Millennium/releases/download/$Version"
    $zipUrl = "$base/$assetBase.zip"
    $work = Join-Path $env:TEMP ('rewired-millennium-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work "$assetBase.zip"
    $extract = Join-Path $work 'extract'
    New-Item -ItemType Directory -Force -Path $work, $extract | Out-Null
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extract -Force
        Copy-Item (Join-Path $extract 'wsock32.dll') (Join-Path $SteamPath 'wsock32.dll') -Force
        $millRoot = Join-Path $SteamPath 'millennium'
        New-Item -ItemType Directory -Force -Path $millRoot | Out-Null
        Copy-Item (Join-Path $extract 'millennium\bin') (Join-Path $millRoot 'bin') -Recurse -Force
        Copy-Item (Join-Path $extract 'millennium\lib') (Join-Path $millRoot 'lib') -Recurse -Force
        return $true
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-RewiredOpenSteamTool {
    param([Parameter(Mandatory)][string]$SteamPath)
    $zipUrl = Get-OpenSteamToolReleaseZipUrl
    $work = Join-Path $env:TEMP ('rewired-ost-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work 'ost.zip'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $work -Force
        foreach ($name in @('dwmapi.dll', 'xinput1_4.dll', 'OpenSteamTool.dll')) {
            $found = Get-ChildItem -Path $work -Filter $name -Recurse -File | Select-Object -First 1
            if (-not $found) { throw "Missing $name in OpenSteamTool archive." }
            Copy-Item -LiteralPath $found.FullName -Destination (Join-Path $SteamPath $name) -Force
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $SteamPath 'config\lua') | Out-Null
        return $true
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-RewiredDesktopShortcut {
    param([Parameter(Mandatory)][string]$ManagerExe)
    if (-not (Test-Path -LiteralPath $ManagerExe)) { return }
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop 'Rewired Manager.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $ManagerExe
    $sc.WorkingDirectory = Split-Path $ManagerExe -Parent
    $sc.Description = 'STLT Rewired Manager'
    $sc.Save()
}

function Invoke-RewiredInstall {
    param(
        [string]$SteamPath = '',
        [switch]$SkipMillennium,
        [switch]$SkipOpenSteamTool,
        [switch]$InstallOpenSteamTool,
        [switch]$SkipShortcut,
        [switch]$FromRepo
    )
    $steam = Get-SteamInstallPath -Override $SteamPath
    $repoRoot = Get-RewiredLocalRepoRoot
    $pluginPath = $null

    if ($FromRepo) {
        if (-not $repoRoot) {
            throw 'FromRepo: run install.ps1 from an STLT-Rewired git checkout (deploy.ps1 not found).'
        }
        $pj = Join-Path $repoRoot 'plugin.json'
        $ver = 'dev'
        if (Test-Path -LiteralPath $pj) {
            try { $ver = (Get-Content -Raw -LiteralPath $pj | ConvertFrom-Json).version } catch { }
        }
        Write-Host "Rewired $ver (local repo)" -ForegroundColor Cyan
    } else {
        $release = Get-RewiredLatestRelease
        Write-Host "Rewired $($release.Version) ($($release.Tag))" -ForegroundColor Cyan
    }

    if (-not $SkipMillennium) {
        $loader = Join-Path $steam 'wsock32.dll'
        $millBin = Join-Path $steam 'millennium\bin'
        if (-not ((Test-Path $loader) -and (Test-Path $millBin))) {
            Write-Host 'Installing Millennium runtime...' -ForegroundColor Cyan
            Install-RewiredMillennium -SteamPath $steam | Out-Null
        } else {
            Write-Host 'Millennium already present.' -ForegroundColor DarkGray
        }
    }

    Write-Host 'Installing Rewired plugin...' -ForegroundColor Cyan
    if ($FromRepo) {
        $pluginPath = Install-RewiredPluginFromLocalRepo -RepoRoot $repoRoot -SteamPath $steam
    } else {
        $pluginPath = Install-RewiredPluginFromUrl -ZipUrl $release.PluginUrl -SteamPath $steam
    }
    Write-Host "Plugin -> $pluginPath" -ForegroundColor Green

    if ($InstallOpenSteamTool) {
        Write-Host 'Installing OpenSteamTool...' -ForegroundColor Cyan
        Install-RewiredOpenSteamTool -SteamPath $steam | Out-Null
        Save-RewiredSharedConfig -SteamPath $steam -PluginPath $pluginPath -UnlockBackend 'opensteamtool' | Out-Null
    } else {
        Save-RewiredSharedConfig -SteamPath $steam -PluginPath $pluginPath -UnlockBackend 'auto' | Out-Null
    }

    Write-Host ''
    Write-Host 'Install complete.' -ForegroundColor Green
    Write-Host '  1. Restart Steam fully (Exit, then relaunch).'
    Write-Host '  2. Enable luatools (Rewired) in Millennium -> Plugins if needed.'
    Write-Host ''
    Write-Host "Update later: irm https://raw.githubusercontent.com/$($script:RewiredGitHubOwner)/$($script:RewiredGitHubRepo)/main/install/Windows-Update.ps1 | iex" -ForegroundColor DarkGray
}

function Invoke-RewiredUpdate {
    param([string]$SteamPath = '', [switch]$SkipManager)
    $steam = Get-SteamInstallPath -Override $SteamPath
    $release = Get-RewiredLatestRelease
    $pluginPath = Join-Path $steam 'millennium\plugins\luatools'
    $current = '0.0.0'
    $pj = Join-Path $pluginPath 'plugin.json'
    if (Test-Path -LiteralPath $pj) {
        try { $current = (Get-Content -Raw -LiteralPath $pj | ConvertFrom-Json).version } catch { }
    }
    if ((Compare-RewiredVersion -Latest $release.Version -Current $current) -le 0) {
        Write-Host "Already on $($release.Version) or newer (current $current)." -ForegroundColor Green
    } else {
        Write-Host "Updating plugin $current -> $($release.Version)..." -ForegroundColor Cyan
        Install-RewiredPluginFromUrl -ZipUrl $release.PluginUrl -SteamPath $steam | Out-Null
    }

    Save-RewiredSharedConfig -SteamPath $steam -PluginPath $pluginPath | Out-Null
    Write-Host 'Update complete. Restart Steam to load the plugin.' -ForegroundColor Green
}

Export-ModuleMember -Function *
