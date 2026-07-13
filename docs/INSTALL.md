# Quick install URLs and one-liners for STLT-Rewired (Rewired).

## Windows (recommended)

### Plugin-first install (default)

1. Install Millennium + plugin:

```powershell
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.ps1 | iex
```

2. Restart Steam fully (Exit, then relaunch).
3. In Steam: open Rewired UI → run Health/Setup fixes when prompted.

### Update

```powershell
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/update.ps1 | iex
```

### Optional “10th line” (Rewired Manager)

Rewired Manager (`Rewired.exe`) is distributed **separately (private)** and is only needed for recovery/edge cases.

### Options (local script)

```powershell
pwsh -NoProfile -File scripts/install.ps1 -SkipMillennium -SkipOpenSteamTool
pwsh -NoProfile -File scripts/install.ps1 -FromRepo   # deploy from git checkout (no GitHub release needed)
pwsh -NoProfile -File scripts/update.ps1 -SteamPath "D:\Steam"
```

| Switch | Effect |
|--------|--------|
| `-SkipMillennium` | Do not install Millennium runtime |
| `-SkipOpenSteamTool` | Do not install OpenSteamTool DLLs |
| `-SkipShortcut` | No desktop shortcut |

**GitHub API rate limit:** If install fails with `API rate limit exceeded`, either wait an hour or set a token first:

```powershell
$env:GITHUB_TOKEN = 'ghp_...'   # or GH_TOKEN
pwsh -NoProfile -File scripts/install.ps1
```

The installer falls back to direct `/releases/latest/download/` URLs when the API is exhausted (no token required).

## Linux

**Full install** — Millennium (via steambrew if missing) + Rewired plugin:

```bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh | bash
```

**Update** (skips Millennium, re-installs plugin preserving `backend/data`):

```bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/update.sh | bash
```

Linux unlock (SLSsteam / ACCELA) is **not** bundled in Rewired.exe — use [enter-the-wired](https://github.com/ciscosweater/enter-the-wired) then `install.sh`. See [ACCELA_STYLE.md](ACCELA_STYLE.md).

Environment overrides: `STEAM_PATH`, `SKIP_MILLENNIUM=1`.

## Auto-update channels

| Component | Mechanism |
|-----------|-----------|
| **Plugin (in Steam)** | `CheckForUpdatesNow` RPC + throttled boot check every 2h via `backend/update.json` → GitHub release `STLT-Rewired.zip` |
| **Script** | Re-run `update.ps1` / `update.sh` one-liners above |

Install URLs are also embedded in `backend/update.json` under `install.*` for in-plugin display via `GetUpdateStatus`.

## First-time maintainers

Publish a GitHub release before one-liner installs work:

```powershell
pwsh -NoProfile -File scripts/build_release.ps1
gh release create v0.1.5 releases/STLT-Rewired.zip --title "STLT-Rewired v0.1.5"
```

## Dev / git checkout

```powershell
pwsh -NoProfile -File deploy.ps1
```
