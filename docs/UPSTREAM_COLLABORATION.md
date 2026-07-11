# Upstream collaboration brief

This document is meant for maintainers of LuaTools / the Steam Plugin rewrite. It explains what STLT-Rewired is, why it exists, what it already ports, and how to evaluate/merge useful work without having to reverse-engineer the fork first.

## Short version

STLT-Rewired is a Windows-first Millennium 3.x Lua backend implementation of the LuaTools Steam plugin surface, with a large set of STLT / SteamTools-Ultimate style augmentations ported into native Millennium IPC.

The goal is not to compete with the official rewrite. The useful outcome is to upstream the parts that are already solved here:

- Millennium 3.x native Lua `callServerMethod` contract.
- Steam UI injection via bundled webkit surface.
- Add-to-Steam flow hardening.
- source chain / Ryuu Premium / Morrenus integration.
- fixes workflow hardening and fallback handling.
- deployment safety for Millennium runtime and plugin updates.
- a large collection of maintenance panels that can be selectively ported or redesigned for v2.

## Lineage / compared inputs

### Gen 1: `ltsteamplugin-main.zip`

Local reference: `C:\Users\sened\Downloads\ltsteamplugin-main.zip`

Observed metadata:

- `plugin.json` name: `luatools`
- common name: `LuaTools`
- version: `9.0.1`
- backend: Lua
- compact repo: `backend/main.lua`, `paths.lua`, `plugin_logger.lua`, `steam_utils.lua`, `public/luatools.js`, themes.
- About 14 backend RPC functions and ~24 frontend `callServerMethod` calls.

This is a small Millennium plugin implementation and a useful baseline for the official plugin contract.

### Gen 2: portable LuaTools app

Local reference: `E:\LuaTools-win-Portable`

Observed metadata:

- packaged via Velopack/Squirrel-style portable layout.
- `current/sq.version`: `LuaTools` version `1.2.2`, `net8-x64-desktop` runtime.
- WPF/.NET desktop app, not a Millennium Lua plugin.
- notable strings/classes in `LuaTools.dll`: `LuaToolsGui`, `PluginInstallerService`, `CefInjectorService`, `LuaToolsApiClient`, `DenuvoFixes`, `CloudRedirectService`, `SteamlessService`, `UnlockerService`, `HubcapService`, `GithubProxy`, `SteamAppInfoCache`.

Gen 2 is a different product surface: a desktop app that can manage/install/plugin-inject and do broader app workflows. It is not drop-in mergeable into the Millennium Lua plugin, but its UX and services are a strong feature reference.

### STLT-Rewired

Local repo: `F:\STLT-Rewired`

Observed metadata:

- `plugin.json` name: `luatools`
- common name: `STLT - Rewired`
- backend: Lua
- target: current Millennium 3.x, tested around `v3.4.0-beta.8`.
- no Python HTTP bridge; no detached daemon; native Millennium `callServerMethod` only.
- 39 backend Lua modules.
- 169 exported backend functions in `backend/main.lua`.
- 100 unique frontend RPC methods in `public/luatools.js`.

## Why Rewired exists

Older STLT-style builds had a rich feature set but were coupled to older injection/bridge assumptions. The specific failure mode we had to eliminate was:

- old injected frontend overriding or bypassing the native Millennium method bridge;
- detached Python HTTP bridge / localhost service assumptions;
- store webkit breakage on current Millennium;
- stale CSP/injection assumptions.

Rewired keeps the feature ambition but uses the modern Millennium shape:

```text
Steam page frontend
  -> Millennium.callServerMethod('luatools', 'PascalCaseMethod', args)
  -> global Lua function in backend/main.lua
  -> cjson/json string response
```

## Current architecture

```text
plugin.json
backend/
  main.lua                 RPC entry points and orchestration
  downloads.lua            source probing/download/install state machine
  fixes.lua                fixes lookup/apply/unfix
  ryuu.lua                 paginated Ryuu catalog search
  api_manifest.lua         source manifest and Ryuu Premium injection
  settings/*               settings + local secret override
  backup/workshop/sync/... feature modules
public/
  luatools.js              injected Steam UI, panels, mod loader, calls backend RPC
.millennium/Dist/webkit.js embedded frontend bundle
scripts/
  build_webkit_bundle.py
  validate_locales.py
deploy.ps1                live deploy + backup/restore + optional Millennium runtime update
```

## IPC rules that matter

- Backend functions exported to Millennium are global PascalCase functions in `backend/main.lua`.
- Frontend calls use `Millennium.callServerMethod('luatools', '<Method>', payload)`.
- Some Millennium paths pass JS objects as Lua tables, while others may sort object keys into positional values. Compatibility wrappers should accept both table and positional forms where user-facing flows depend on them.
- Return values should follow the project convention: JSON-safe tables encoded/returned through the existing helpers.
- Frontend must not assume optional nested backend payloads exist; guard before dereference.

## Recent hardening worth upstreaming

### Add-to-Steam / no-license guard

Problem: immediately triggering `steam://install/<appid>` after writing Lua activation files can produce a Steam `No License` prompt because Steam has not reloaded the injected app license state yet.

Implemented behavior:

- `AutoFinalizeActivation` writes/finishes activation without auto-launching `steam://install`.
- UI communicates restart-first flow.
- explicit manual `StartDownloadNoRestart` remains available for users who intentionally want to try.

### Ryuu Premium source and catalog

Implemented:

- `backend/api.json` includes `Ryuu Premium` as `https://generator.ryuu.lol/api/download/<appid>`.
- `backend/api_manifest.lua` prevents duplicate generator entries and prefers local Ryuu session when configured.
- `backend/ryuu.lua` uses paginated `/api/games?limit=40&page=N&search=<query>` rather than giant `files/games.json`, which can hang/chunk indefinitely in the Steam/Millennium path.
- `backend/data/secrets.local.json` stores `ryuuSession` locally; it is gitignored and preserved by deploy.

### Fixes workflow

Implemented:

- upstream fixes index failure/429 is non-fatal.
- default `genericFix` / `onlineFix` objects are still returned so the UI does not crash.
- Ryuu fixes page is used as a best-effort fallback source.
- Windows extraction uses generated PowerShell scripts with explicit System32 `tar.exe` and `curl.exe` to avoid MSYS PATH surprises.
- archive entries are listed and validated before extraction:
  - no empty paths;
  - no rooted/absolute paths;
  - no drive prefixes;
  - no `:`;
  - no `..` path segments.
- state JSON is ASCII to avoid Windows PowerShell UTF-8 BOM issues with Lua JSON decoders.
- partial zip/script/state cleanup is performed on success/failure.

### Deploy hardening

Implemented in `deploy.ps1`:

- backups outside `millennium/plugins` to avoid duplicate `plugin.json` name collisions.
- preserve `backend/data` across deploys.
- parse/runtime checks for Millennium beta archive layout before replacing runtime.
- Steam process preflight for runtime update.
- rollback helper for partial Millennium runtime update failure.
- native command `$LASTEXITCODE` checks.

## Contribution posture

The cleanest collaboration strategy is not to ask upstream to accept all of STLT-Rewired as-is. Better:

1. Split features into small independent PRs or patches.
2. Keep local secret/session handling out of committed defaults.
3. Prefer backend modules with narrow RPC surfaces.
4. Document every feature with:
   - user problem;
   - current implementation;
   - files touched;
   - risk;
   - test/verification recipe.
5. Offer Rewired as a working integration lab for Windows/Millennium 3.x while upstream v2 stabilizes.

## Suggested upstream-ready PR slices

1. Ryuu Premium source + local session support.
2. Ryuu catalog search via paginated `/api/games`.
3. Fixes-index resilience + safe frontend guards.
4. Safe fix archive extraction and unfix log format.
5. No-license-safe Add-to-Steam UX.
6. Deployment/runtime backup safety.
7. Diagnostic report module (`GetMillenniumHealth`, app diagnostics, source stats).

## Non-goals / things to discuss before upstreaming

- Linux-only SLS/Proton/compat-tool flows from older STLT are intentionally not first-class in this Windows Millennium plugin.
- Desktop app features from Gen 2 should not be copy-pasted into the Lua plugin. Treat them as UX/service references.
- CloudRedirect/STFixer integration should remain explicit-user-action only; do not silently patch SteamTools/Steam cloud layers.
- Any source that uses cookies/API keys must keep secrets local, gitignored, and never printed in logs.
