# Technical fork brief

This document is meant for future maintainers, contributors, and any LuaTools / Steam Plugin developers who want to understand STLT-Rewired without reverse-engineering the fork first. It can be used for upstream collaboration, but the project should stand on its own as an independent Windows-first power-user fork.

## Short version

STLT-Rewired is a Windows-first Millennium 3.x Lua backend implementation of the LuaTools Steam plugin surface, with a large set of STLT / SteamTools-Ultimate style augmentations ported into native Millennium IPC.

The project goal is not to beg for acceptance from any single upstream channel. The useful outcome is to keep a working integration lab and make the solved parts easy to reuse, review, or upstream later:

- Millennium 3.x native Lua `callServerMethod` contract.
- Steam UI injection via bundled webkit surface.
- Add-to-Steam flow hardening.
- source chain / Ryuu Premium / Morrenus integration.
- fixes workflow hardening and fallback handling.
- deployment safety for Millennium runtime and plugin updates.
- a large collection of maintenance panels that can be selectively ported or redesigned for v2.

## Lineage / compared inputs

### Gen 1: `ltsteamplugin-main.zip`

Local references:

- archive: `C:\Users\sened\Downloads\ltsteamplugin-main.zip`
- upstream repo: https://github.com/madoiscool/ltsteamplugin

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

Companion / tooling on the same machine:

- `F:\Rewired-Manager` — source for Rewired Manager (Ryuu/source health probes, plugin discovery)
- `F:\Rewired-Manager-Binaries` — published manager zips
- `F:\dotnet-sdk` — local .NET SDK used to build the manager

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

### Add-to-Steam / no-restart flow

Problem: immediately triggering `steam://install/<appid>` after writing Lua activation files can produce a Steam `No License` prompt on some builds because Steam has not reloaded the injected app license state yet.

Current behavior (matches upstream Gen1 `steam://install` links in the loaded-apps popup):

- `AutoFinalizeActivation` triggers `steam://install/<appid>` on the running client after the `.lua` is written.
- UI shows “Downloading — no restart needed” when that succeeds.
- Manual **Try download (no restart)** and **Restart Steam to finish** remain as fallbacks when Steam still shows No License.

Ryuu catalog search must stay bounded: Rewired Manager probes with a **single** paginated request (`limit=40&page=1&search=…`). The plugin backend caps at **3 pages** with short timeouts so Millennium’s blocking Lua thread cannot freeze Steam (never scan 80 pages synchronously inside the webkit path).

### Ryuu Premium source and catalog

- `backend/api.json` includes `Ryuu Premium` as `https://generator.ryuu.lol/api/download/<appid>`.
- `backend/api_manifest.lua` prevents duplicate generator entries and prefers local Ryuu session when configured.
- `backend/ryuu.lua` uses the same paginated API as `F:\Rewired-Manager\...\SourceHealthService.cs` (max 3 pages, 8s timeout).
- Ryuu catalog **+ Add** uses `StartAddViaLuaToolsFromUrl` directly (avoids synchronous probe-all-APIs loop).
- `backend/data/secrets.local.json` stores `ryuuSession` locally; gitignored and preserved by deploy.

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
