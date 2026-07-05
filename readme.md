# STLT — Rewired

LuaTools rebuilt on the modern **Millennium 3.x Lua backend** (piqseu base), with the
SteamTools-Ultimate (STLT) feature set ported in. Native `callServerMethod` IPC — no Python
HTTP bridge, no persistent daemon. Windows.

> A Millennium plugin for the Steam client. It adds a game-manifest/source workflow plus a set
> of maintenance tools (diagnostics, backup/restore, achievements, workshop, sync, key vault,
> and more) to the Steam UI.

## Requirements

- **Steam** (desktop client) on **Windows**.
- **Millennium 3.x** installed and enabled (`v3.3.1` is the tested baseline).
- The backend runs as Lua inside Millennium — no Python runtime is required or used.

## Install

Deploy the shipped surface into the live Millennium plugins directory with the included script:

```powershell
pwsh -File deploy.ps1            # deploy (backs up the current plugin first)
pwsh -File deploy.ps1 -Restore   # roll back to the last backup
```

The script copies only the runtime surface (`backend/`, `public/`, `.millennium/`,
`plugin.json`) and skips dev/VCS files. Backups are written to
`…\Steam\millennium\_plugin-backups\` — **outside** `plugins\` — because Millennium keys
plugins by the `name` field in `plugin.json`, not the folder name; a second folder declaring
`name: "luatools"` (e.g. a backup left inside `plugins\`) collides and prevents the Steam UI
from starting.

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
  "ryuuSession": "session=…",
  "morrenusApiKey": "smm_…"
}
```

- **`ryuuSession`** — the Ryuu Premium session cookie (the `session=…` header string from the
  Ryuu generator). It is attached as `Cookie:` on Ryuu availability checks and the download
  request, so authenticated Ryuu content works.
- **`morrenusApiKey`** — the hubcap/Morrenus API key used for `<moapikey>` and hub status calls.

This file is never committed (see `.gitignore`) and is carried across deploys by `deploy.ps1`.

## Architecture

- **Backend** — Lua modules under `backend/`, one cluster per concern (sources/downloads,
  manifests, DLC, achievements, workshop, backup, sync, account, key vault, diagnostics,
  sentinel, …). RPC entry points are global functions in `backend/main.lua` that Millennium
  dispatches via `callServerMethod`.
- **Frontend** — `public/luatools.js`, injected into the Steam UI (webkit) via Millennium's
  `add_browser_js` / `add_browser_css`; the rich UI bundle lives in `.millennium/Dist/`.
- **IPC** — native Millennium `callServerMethod('luatools', '<Method>', args)`; method names are
  PascalCase and map 1:1 to the global Lua functions.

## Development conventions

- No telemetry, no heavy dependencies, no persistent daemons.
- Millennium IPC method names are **PascalCase**.
- Backend logging via `print('[LuaTools] …')` (see `plugin_logger`), not a logging framework.
- UI kept compact for 4K @ 175–200% scaling (modals ≤ 580px).

## Rollback

`pwsh -File deploy.ps1 -Restore` restores the most recent pre-deploy backup from
`…\Steam\millennium\_plugin-backups\`. Restart Steam to load it.
