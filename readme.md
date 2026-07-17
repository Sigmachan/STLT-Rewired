# STLT — Rewired

**Rewired Manager** is the primary control plane (unlock backend, add games, deploy). The Millennium
plugin is optional in-Steam UI on top of the same backend.

LuaTools rebuilt on **Millennium 3.x Lua** (piqseu base), with STLT's SteamTools-Ultimate features
ported in. Native `callServerMethod` IPC — no Python HTTP bridge.

> See `docs/PRODUCTION_STACK.md` for the recommended install path (Manager + OpenSteamTool, Millennium optional).

## Quick install

**Windows (full stack):**

```powershell
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows.ps1 | iex
```

**Windows (update):**

```powershell
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows-Update.ps1 | iex
```

**Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh | bash
```

Installs ACCELA + SLSsteam (enter-the-wired), Millennium if needed, and the Rewired plugin.
Unlock-only: `install/Linux-Unlock.sh`. Details: `docs/INSTALL.md`.

## Project docs

- `docs/INSTALL.md` — one-liner URLs, install/update scripts, auto-update channels.
- `install/README.md` — installer names (Windows / Linux / Unlock).
- `docs/ARCHITECTURE.md` — runtime shape, backend modules, RPC surface, safety model.
- `docs/GEN1_GEN2_COMPARISON.md` — notes from the Gen 1 plugin archive and Gen 2 portable app.
- `docs/COMPETITIVE_BASELINE.md` — official LuaTools/Gen2 baseline and Rewired differentiators.
- `docs/REWIRED_MANAGER_PLAN.md` — **Rewired Manager** (our desktop app) roadmap.
- `docs/FORK_BRIEF.md` — technical brief for maintainers (architecture, lineage, non-goals).

## Requirements

- **Steam** (desktop client) on **Windows**.
- **Millennium 3.x** installed and enabled (`v3.4.0-beta.8` is the current tested target).
- The backend runs as Lua inside Millennium — no Python runtime is required or used.

## Install

Deploy the shipped surface into the live Millennium plugins directory with the included script:

```powershell
pwsh -File deploy.ps1                         # deploy (backs up the current plugin first)
pwsh -File deploy.ps1 -InstallMillenniumBeta  # update Millennium beta, then deploy
pwsh -File deploy.ps1 -Restore                # roll back to the last plugin backup
```

The script copies only the runtime surface (`backend/`, `public/`, `.millennium/`,
`plugin.json`) and skips dev/VCS files. Backups are written to
`…\Steam\millennium\_plugin-backups\` — **outside** `plugins\` — because Millennium keys
plugins by the `name` field in `plugin.json`, not the folder name; a second folder declaring
`name: "luatools"` (e.g. a backup left inside `plugins\`) collides and prevents the Steam UI
from starting.

With `-InstallMillenniumBeta`, the script downloads the tested Millennium beta runtime,
checks its SHA256 file, backs up the current Millennium loader/runtime under
`…\Steam\millennium\_millennium-backups\`, then deploys LuaTools as usual. Use
`-MillenniumVersion <tag>` or `-SteamPath <path>` if your setup differs from the defaults.

After deploying: fully restart Steam, then confirm `luatools` is enabled in Millennium settings.

## Configuration

### Settings

In-client settings (LuaTools → settings) cover language/locale, theme, fast-download source
auto-select, and the Morrenus (hubcap) API key. Values persist in `backend/data/settings.json`.

### Sources

Download sources are defined in `backend/api.json` (`Morrenus`, `Ryuu`, and others). Each entry
has a URL template with `<appid>` (and `<moapikey>` for Morrenus). Availability is probed per
source before a download; `fastDownload` auto-selects the first available source.

### Local secrets (persist across updates)

Personal credentials that you don't want re-entering after every redeploy live in a
**gitignored** file that the backend reads at runtime and prefers over the in-client settings:

`backend/data/secrets.local.json`

```json
{
  "ryuuSession": "<Ryuu Cookie header>",
  "morrenusApiKey": "<Morrenus API key>"
}
```

- **`ryuuSession`** — the Ryuu Premium session cookie header string from the
  Ryuu generator). It is attached as `Cookie:` on Ryuu availability checks and the download
  request, so authenticated Ryuu content works.
- **`morrenusApiKey`** — the hubcap/Morrenus API key used for `<moapikey>` and hub status calls.

This file is never committed (see `.gitignore`) and is carried across deploys by `deploy.ps1`.

## Architecture

- **Backend** — Lua modules under `backend/`, one cluster per concern (sources/downloads,
  manifests, DLC, achievements, workshop, backup, sync, account, key vault, diagnostics,
  sentinel, …). RPC entry points are global functions in `backend/main.lua` that Millennium
  dispatches via `callServerMethod`.
- **Frontend** — `public/luatools.js`, embedded into `.millennium/Dist/webkit.js` by
  `scripts/build_webkit_bundle.py` and loaded through Millennium's webkit module path. Do not
  use `add_browser_js` / `add_browser_css` for store-page injection on Millennium 3.4; Steam CSP
  blocks those `millennium.host/v1/themes/...` script URLs.
- **IPC** — native Millennium `callServerMethod('luatools', '<Method>', args)`; method names are
  PascalCase and map 1:1 to the global Lua functions.

## Development conventions

- No telemetry, no heavy dependencies, no persistent daemons.
- Millennium IPC method names are **PascalCase**.
- Backend logging via `print('[LuaTools] …')` (see `plugin_logger`), not a logging framework.
- UI kept compact for 4K @ 175–200% scaling (modals ≤ 580px).
- Compatibility target is Millennium `v3.4.0-beta.8`; `GetMillenniumHealth` reports the
  loaded Millennium version plus required Lua API availability.
- Run `python scripts/build_webkit_bundle.py` after editing `public/luatools.js`; `deploy.ps1`
  runs it automatically before copying the runtime surface.

## Rollback

`pwsh -File deploy.ps1 -Restore` restores the most recent pre-deploy backup from
`…\Steam\millennium\_plugin-backups\`. Restart Steam to load it.
