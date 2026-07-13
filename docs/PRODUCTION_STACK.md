# Production stack

Rewired ships as a **two-layer product**. Millennium is optional when Manager + an unlock backend are installed.

## Layers

| Layer | Component | Required? |
|-------|-----------|-------------|
| Control plane | **Rewired Manager** (`manager/`) | Yes (primary UI) |
| Unlock / injector | OpenSteamTool (default), SteamTools, or LumaCore | Yes |
| In-Steam UI | Millennium `luatools` plugin | Optional |

Shared configuration: `%LOCALAPPDATA%\Rewired\rewired.json`  
Plugin and Manager both read it for unlock backend preference and Steam path.

## Default Windows install (recommended)

1. Build or download `RewiredManager-win-x64-framework-dependent.zip`.
2. Open **Rewired Manager → System**.
3. Set Steam path → **Install OpenSteamTool** (pulls latest [OpenSteam001/OpenSteamTool](https://github.com/OpenSteam001/OpenSteamTool) release).
4. **Secrets** tab → Ryuu session + ManifestHub key → Save → Test.
5. **Restart Steam** from Manager.
6. **Add game** tab: enter AppID → Download & install.
7. Optional: **Deploy** tab or `deploy.ps1` for in-Steam Rewired UI.

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
| Rewired Manager | **System → Check for updates** (GitHub latest release) |
| Script | `update.ps1` / `update.sh` one-liners — see `docs/INSTALL.md` |

One-liner **install URLs** (also in `backend/update.json`):

```powershell
# Windows full install
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.ps1 | iex
```

```bash
# Linux plugin + Millennium
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh | bash
```

Publish releases with both zips attached (`scripts/publish_release.ps1`) before one-liners work for end users.

## Build & release

```powershell
pwsh -NoProfile -File scripts/build_release.ps1
pwsh -NoProfile -File manager/scripts/publish-manager.ps1
```

Attach both zips to GitHub release:

- `STLT-Rewired.zip` — Millennium plugin (optional UI)
- `RewiredManager-win-x64-framework-dependent.zip` — control plane

## RPC

Plugin exposes `GetUnlockBackendStatus` for in-Steam diagnostics aligned with Manager.

## Philosophy

- Manager owns install, unlock, add-game, deploy, restart.
- Plugin owns in-Steam UX when Millennium is present.
- No upstream collaboration dependency; competitive parity with SteaMidra / Gen2 / OpenSteamTool-GUI, clean-room implementation.
