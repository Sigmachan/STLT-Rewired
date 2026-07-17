# Quick install URLs and one-liners for STLT-Rewired (Rewired).

Short entrypoints at repo root (`install.sh` / `install.ps1`).  
Full scripts live in **`install/`**. Dev/build helpers stay in `scripts/`.  
See `install/README.md` for the file table.

Preferred AIO URLs: **`https://sigmachan.ru/install.ps1`** (Windows) and **`https://sigmachan.ru/install`** (Linux).  
(`update` / `unlock` aliases exist; normal users only need **install**.)


## Windows (recommended)

### AIO install (default)

Millennium + OpenSteamTool unlock + Rewired plugin (Millennium tag resolved from GitHub **latest** release, including prereleases):

```powershell
irm https://sigmachan.ru/install.ps1 | iex
```

`unlockBackend` is saved as **auto** — if SteamTools is already installed, Rewired prefers it over OpenSteamTool.

Then:
1. Restart Steam fully (Exit, then relaunch).
2. In Steam: open Rewired UI → run Health/Setup fixes when prompted.

Re-run the **same** install command anytime to refresh the plugin (Millennium / OpenSteamTool are skipped if already present).

### Optional “10th line” (Rewired Manager)

Rewired Manager (`Rewired.exe`) is distributed **separately (private)** and is only needed for recovery/edge cases.

### Options (local script)

```powershell
pwsh -NoProfile -File install/Windows.ps1 -SkipMillennium
pwsh -NoProfile -File install/Windows.ps1 -SkipOpenSteamTool   # plugin/Millennium only
pwsh -NoProfile -File install/Windows.ps1 -FromRepo   # deploy from git checkout (no GitHub release needed)
pwsh -NoProfile -File install/Windows.ps1 -SteamPath "D:\Steam"
```

| Switch | Effect |
|--------|--------|
| `-SkipMillennium` | Do not install Millennium runtime |
| `-SkipOpenSteamTool` | Do not install OpenSteamTool (AIO includes it by default) |

`-SkipManager` / `-SkipShortcut` are accepted for older one-liners but currently have no effect (Manager is distributed separately).

**GitHub API rate limit:** If install fails with `API rate limit exceeded`, either wait an hour or set a token first:

```powershell
$env:GITHUB_TOKEN = 'ghp_...'   # or GH_TOKEN
pwsh -NoProfile -File install/Windows.ps1
```

The installer falls back to direct `/releases/latest/download/` URLs when the API is exhausted (no token required).

## Linux

**AIO (recommended)** — ACCELA + SLSsteam + Millennium + Rewired plugin in one shot:

```bash
curl -fsSL https://sigmachan.ru/install | bash
```

Unlock Lua lands in `Steam/config/stplug-in/`. Steam auto-detect covers **native**, **Flatpak**, and **Snap** roots — that already includes **CachyOS**, **Bazzite**, **ChimeraOS**, **Nobara**, **Ximper/ALT**, **Ubuntu**, **Fedora**, Arch, Debian, openSUSE, and similar. Skip pieces with env vars if needed:

| Env | Effect |
|-----|--------|
| `SKIP_UNLOCK=1` | Do not install ACCELA/SLSsteam |
| `SKIP_MILLENNIUM=1` | Do not install Millennium |
| `SKIP_PLUGIN=1` | Unlock/Millennium only |
| `FORCE=1` | Re-run unlock installer even if ACCELA/SLS already present |
| `STEAM_PATH=...` | Override Steam root (native or Flatpak data dir) |
| `MILLENNIUM_VERSION=...` | Pin Millennium GitHub tag (default: **latest** release including prereleases) |

Examples when auto-detect fails (env must be on the **bash** side of the pipe — `VAR=x curl | bash` does **not** pass `VAR` into the installer):

```bash
# Native Steam (CachyOS, Nobara, Ubuntu, Fedora, Ximper, ChimeraOS, …)
curl -fsSL https://sigmachan.ru/install | STEAM_PATH="$HOME/.local/share/Steam" bash

# Flatpak Steam (Bazzite and many desktops)
curl -fsSL https://sigmachan.ru/install | STEAM_PATH="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" bash

# Force unlock reinstall
curl -fsSL https://sigmachan.ru/install | FORCE=1 bash
```

Re-run the **same** install command to refresh the plugin (unlock / Millennium are skipped if already present).

Credits: [ciscosweater/enter-the-wired](https://github.com/ciscosweater/enter-the-wired), [AceSLS/SLSsteam](https://github.com/AceSLS/SLSsteam), Deadboy666 Headcrab.

## Auto-update channels

| Component | Mechanism |
|-----------|-----------|
| **Plugin (in Steam)** | `CheckForUpdatesNow` RPC + throttled boot check every 2h via `backend/update.json` → GitHub release `STLT-Rewired.zip` |
| **Script** | Re-run the same `install` / `install.ps1` one-liner |

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
