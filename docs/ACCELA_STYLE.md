# ACCELA-style stack comparison

Rewired on **Windows** mirrors the **ACCELA + SLSsteam** workflow on **Linux** — one desktop app is the control plane; unlock loads when Steam starts through the stack.

## Role mapping

| Linux (enter-the-wired) | Windows (Rewired) |
|-------------------------|-------------------|
| **ACCELA** — desktop app, add games, settings | Rewired plugin UI (default) / Rewired Manager (`Rewired.exe`, optional “10th line”) |
| **SLSsteam** — `LD_AUDIT` unlock at Steam load | **OpenSteamTool** — DLLs in Steam root, `config/lua` |
| **cyberia / Millennium** (optional) — in-Steam UI | **Millennium + luatools plugin** — store “Add via Rewired” |
| Start Steam **after** stack is installed | Restart Steam after setup (plugin-first) |

## How to use (Windows, ACCELA-like)

1. Install plugin + unlock backend (OpenSteamTool) via `docs/INSTALL.md`.
2. In Steam: Rewired UI → Health/Setup → apply fixes (OST install, Lua dir).
3. Restart Steam.
4. Add game from in-Steam UI (AppID).

OpenSteamTool loads when its DLLs present in Steam root. If unlock missing, re-run Setup/Health fixes or use Manager (private) as a recovery tool.

## Linux today

`install/Linux.sh` installs the **full stack** by default:

1. **ACCELA + SLSsteam** via the community [enter-the-wired](https://github.com/ciscosweater/enter-the-wired) installer (Headcrab for SLSsteam)
2. Millennium (steambrew) if missing
3. Rewired plugin into `$STEAM/millennium/plugins/luatools`
4. Shared config → `~/.local/share/Rewired/rewired.json` (`unlockBackend: steamtools`)

```bash
# Full stack
curl -fsSL https://sigmachan.ru/install | bash

# Unlock only (ACCELA + SLSsteam)
curl -fsSL https://sigmachan.ru/unlock | bash

# Plugin/Millennium without reinstalling unlock
SKIP_UNLOCK=1 curl -fsSL https://sigmachan.ru/install | bash
```

We do **not** vendor ACCELA binaries in this repo — the installer downloads the current enter-the-wired / Headcrab releases at install time.

## What we are not doing

- Shipping closed ACCELA binaries inside Rewired.
- Re-adding the old STLT `accela_launcher.py` download handoff in the Millennium plugin (Linux-only, removed for Windows-first focus).

## Deep integration (optional later)

- Linux: Rewired calls ACCELA `run.sh` for depot download after writing `.lua` (old STLT 10.1 flow).
- Windows: custom CEF injector to drop Millennium (Gen2 LuaLoader parity).
