# Production stack

Rewired ships as a **plugin-first product**. Manager exists as an optional “10th line” recovery/control-plane tool and is distributed separately (private).

## Layers

| Layer | Component | Required? |
|-------|-----------|-------------|
| Control plane | Rewired Manager (`Rewired.exe`) | Optional (10th line) |
| Unlock / injector | OpenSteamTool (default), SteamTools, or LumaCore | Yes |
| In-Steam UI | Millennium `luatools` plugin | Optional |

Shared configuration: `%LOCALAPPDATA%\Rewired\rewired.json`  
Plugin and Manager both read it for unlock backend preference and Steam path.

## Default Windows install (recommended)

1. Install Millennium + plugin: `docs/INSTALL.md` (one-liner or manual deploy).
2. In Steam: open Rewired UI → run health/setup fixes (OpenSteamTool install, Lua dir, etc).
3. Restart Steam when prompted.

Manager: private distribution, use only when plugin-side setup not enough.

OpenSteamTool reads Lua from `Steam/config/lua/`. SteamTools and LumaCore use `config/stplug-in/`.  
The plugin backend (`unlock_paths.lua`) picks the directory automatically.

## Unlock backends

| Backend | Lua path | Install |
|---------|----------|---------|
| OpenSteamTool | `config/lua` | Manager one-click or manual DLL copy |
| SteamTools | `config/stplug-in` | steamtools.net |
| LumaCore | `config/stplug-in` | SteaMidra Auto LC Setup or manual |
| Linux (future) | `config/stplug-in` | SLSsteam + enter-the-wired |

## Auto-update

| Channel | How |
|---------|-----|
| Plugin in Steam | `GetUpdateStatus` / `CheckForUpdatesNow`; boot check every 2h (`auto_update.maybe_check_on_boot`) |
| Script | `update.ps1` / `update.sh` one-liners — see `docs/INSTALL.md` |

One-liner **install URLs** (also in `backend/update.json`):

```powershell
# Windows full install
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows.ps1 | iex
```

```bash
# Linux plugin + Millennium
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh | bash
```

Publish releases with plugin zip attached (`scripts/publish_release.ps1`) before one-liners work for end users.

## Build & release

```powershell
pwsh -NoProfile -File scripts/build_release.ps1
```

Attach plugin zip to GitHub release:

- `STLT-Rewired.zip` — Millennium plugin (optional UI)

## RPC

Plugin exposes `GetUnlockBackendStatus` for in-Steam diagnostics aligned with Manager.

## Philosophy

- Manager owns install, unlock, add-game, deploy, restart.
- Plugin owns in-Steam UX when Millennium is present.
- No upstream collaboration dependency; competitive parity with SteaMidra / Gen2 / OpenSteamTool-GUI, clean-room implementation.
