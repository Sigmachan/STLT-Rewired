# ACCELA-style stack comparison

Rewired on **Windows** mirrors the **ACCELA + SLSsteam** workflow on **Linux** — one desktop app is the control plane; unlock loads when Steam starts through the stack.

## Role mapping

| Linux (enter-the-wired) | Windows (Rewired) |
|-------------------------|-------------------|
| **ACCELA** — desktop app, add games, settings | **Rewired.exe** — setup wizard, secrets, add game |
| **SLSsteam** — `LD_AUDIT` unlock at Steam load | **OpenSteamTool** — DLLs in Steam root, `config/lua` |
| **cyberia / Millennium** (optional) — in-Steam UI | **Millennium + luatools plugin** — store “Add via Rewired” |
| Start Steam **after** stack is installed | **Launch Steam** in Rewired (not the plain Steam shortcut) |

## How to use (Windows, ACCELA-like)

1. Run **Rewired.exe** → **Set up Rewired** (OST + in-Steam UI once).
2. **Secrets** → Ryuu + ManifestHub.
3. **Add game** → AppID.
4. **Launch Steam** from Rewired (primary button) — same idea as “restart Steam through SLSsteam” on Linux.

Do not pin the raw Steam icon for daily use after setup; OpenSteamTool only loads when Steam starts with the stack in place.

## Linux today

Rewired does **not** bundle ACCELA or SLSsteam (dropped from the plugin; see `REWIRED-PLAN.md`).

**Supported path:**

```bash
# 1. Unlock stack (ACCELA + SLSsteam)
curl -fsSL https://raw.githubusercontent.com/ciscosweater/enter-the-wired/main/enter-the-wired | bash

# 2. In-Steam UI (Millennium + plugin)
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh | bash
```

Future: a **Linux Rewired** build could wrap `enter-the-wired` install + plugin deploy in one wizard (same UX as Windows).

## What we are not doing

- Shipping closed ACCELA binaries inside Rewired.
- Re-adding the old STLT `accela_launcher.py` download handoff in the Millennium plugin (Linux-only, removed for Windows-first focus).

## Deep integration (optional later)

- Linux: Rewired calls ACCELA `run.sh` for depot download after writing `.lua` (old STLT 10.1 flow).
- Windows: custom CEF injector to drop Millennium (Gen2 LuaLoader parity).
