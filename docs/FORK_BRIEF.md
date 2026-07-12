# Technical fork brief

For maintainers and contributors: what STLT-Rewired is, how it is built, and how it differs from older inputs.

**Rewired is an independent product.** We do not coordinate with, seek approval from, or depend on any official LuaTools / Millennium community channels.

## Short version

STLT-Rewired is a Windows-first Millennium 3.x Lua backend implementation of the LuaTools Steam plugin surface, with STLT / SteamTools-Ultimate style augmentations ported into native Millennium IPC.

Goals:

- Millennium 3.x native Lua `callServerMethod` contract.
- Steam UI via bundled webkit surface.
- Add-to-Steam flow hardening.
- Source chain / Ryuu Premium / ManifestHub integration.
- Fixes workflow hardening and fallback handling.
- Deployment safety for Millennium runtime and plugin updates.
- Maintenance panels (backup, diagnostics, sync, key vault, etc.).

## Lineage / compared inputs

### Gen 1: `ltsteamplugin` (piqseu / madoiscool)

Reference archive/repo for the **small Millennium plugin contract** (~14 RPCs). Rewired keeps the `luatools` plugin name and IPC shape for drop-in compatibility.

### Gen 2: portable LuaTools desktop app

Local reference only (`E:\LuaTools-win-Portable` or similar). WPF/.NET app — **UX and feature ideas**, not code to merge. Gen2 services (installer, injector, Hubcap, CloudRedirect, etc.) inform Rewired Manager and in-Steam panels; we implement our own clean-room versions.

### STLT-Rewired (this repo)

- `plugin.json` name: `luatools`, common name: `Rewired`
- Target: Millennium 3.x (`v3.4.0-beta.8` tested)
- No Python HTTP bridge; native `callServerMethod` only
- Plugin: `backend/`, `public/`, `.millennium/`
- Manager: `manager/RewiredManager.App/` (WPF companion)
- Releases: `releases/STLT-Rewired.zip` + `RewiredManager-win-x64-framework-dependent.zip`

## Why Rewired exists

Older STLT-style builds used a detached Python bridge and hand-injected JS that broke on modern Millennium 3.x. Rewired uses:

```text
Steam page frontend
  -> Millennium.callServerMethod('luatools', 'PascalCaseMethod', args)
  -> global Lua function in backend/main.lua
  -> JSON string response
```

## Architecture

```text
plugin.json
backend/                 Lua modules + RPC entry points (main.lua)
public/luatools.js       Steam UI (embedded into .millennium/Dist/webkit.js)
manager/                 Rewired Manager desktop app (optional)
deploy.ps1               Live deploy + backup; preserves backend/data
```

## IPC rules

- Backend exports global PascalCase functions; frontend calls `callServerMethod('luatools', …)`.
- Accept both table and positional arg shapes where Millennium paths differ.
- Returns must be JSON-safe strings through existing helpers.
- Guard optional nested payloads on the frontend.

## Recent hardening (implementation notes)

### Add-to-Steam / no-restart

- `AutoFinalizeActivation` uses `steam://install/<appid>` after `.lua` is written.
- Manual fallbacks when Steam still shows No License.

### Ryuu Premium + catalog

- `backend/api.json` includes Ryuu Premium; session in gitignored `secrets.local.json`.
- Catalog search is paginated and capped (max 3 pages, short timeouts) so Lua does not block the webkit thread.

### Fixes workflow

- Index failures / 429 are non-fatal; Ryuu fallback when available.
- Archive extraction validates paths (no traversal, no absolute paths).
- Windows uses explicit System32 `tar.exe` / `curl.exe`.

### Deploy

- Backups outside `millennium/plugins` (duplicate `luatools` name collision).
- Preserves `backend/data` across deploys.
- Millennium runtime update preflight + rollback helpers.

## Non-goals

- Linux/Proton-first flows from older STLT.
- Copying Gen2 closed binaries into the plugin.
- Silent SteamTools / CloudRedirect / cloud-layer patching.
- Committing or logging cookies, API keys, or session material.
