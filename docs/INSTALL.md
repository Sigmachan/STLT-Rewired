# Quick install URLs and one-liners for STLT-Rewired (Rewired).

Short entrypoints at repo root (`i` / `i.ps1` / `u` / `u.ps1` / `unlock`).  
Full scripts live in **`install/`**. Dev/build helpers stay in `scripts/`.  
See `install/README.md` for the file table.

One-liners use **jsDelivr** (`cdn.jsdelivr.net/gh/...@main/...`) — shorter than `raw.githubusercontent.com` and the usual CDN mirror for GitHub files. A custom domain (`get.example.com`) is the only way to go shorter still.

## Windows (recommended)

### Plugin-first install (default)

1. Install Millennium + plugin:

```powershell
irm https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/i.ps1 | iex
```

2. Restart Steam fully (Exit, then relaunch).
3. In Steam: open Rewired UI → run Health/Setup fixes when prompted.

### Update

```powershell
irm https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/u.ps1 | iex
```

### Optional “10th line” (Rewired Manager)

Rewired Manager (`Rewired.exe`) is distributed **separately (private)** and is only needed for recovery/edge cases.

### Options (local script)

```powershell
pwsh -NoProfile -File install/Windows.ps1 -SkipMillennium -SkipOpenSteamTool
pwsh -NoProfile -File install/Windows.ps1 -FromRepo   # deploy from git checkout (no GitHub release needed)
pwsh -NoProfile -File install/Windows-Update.ps1 -SteamPath "D:\Steam"
```

| Switch | Effect |
|--------|--------|
| `-SkipMillennium` | Do not install Millennium runtime |
| `-SkipOpenSteamTool` | Do not install OpenSteamTool DLLs |
| `-SkipShortcut` | No desktop shortcut |

**GitHub API rate limit:** If install fails with `API rate limit exceeded`, either wait an hour or set a token first:

```powershell
$env:GITHUB_TOKEN = 'ghp_...'   # or GH_TOKEN
pwsh -NoProfile -File install/Windows.ps1
```

The installer falls back to direct `/releases/latest/download/` URLs when the API is exhausted (no token required).

## Linux

**Full stack (recommended)** — Millennium + Rewired plugin + **ACCELA + SLSsteam**:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/i | bash
```

This runs the community [enter-the-wired](https://github.com/ciscosweater/enter-the-wired) combo installer (ACCELA + Headcrab/SLSsteam), then installs Millennium (if missing) and the Rewired plugin. Unlock scripts land in `Steam/config/stplug-in/`.

| Env | Effect |
|-----|--------|
| `SKIP_UNLOCK=1` | Do not install ACCELA/SLSsteam |
| `SKIP_MILLENNIUM=1` | Do not install Millennium |
| `SKIP_PLUGIN=1` | Unlock/Millennium only |
| `STEAM_PATH=...` | Override Steam root |
| `FORCE=1` | With unlock-only script: reinstall even if present |

**Unlock only** (ACCELA + SLSsteam):

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/unlock | bash
# FORCE=1 curl -fsSL …/unlock | bash
```

**Update plugin** (skips Millennium + unlock, preserves `backend/data`):

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/u | bash
```

Credits: [ciscosweater/enter-the-wired](https://github.com/ciscosweater/enter-the-wired), [AceSLS/SLSsteam](https://github.com/AceSLS/SLSsteam), Deadboy666 Headcrab.

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
