# Gen1 / Gen2 / STLT-Rewired comparison

This document records what was inspected from reference inputs (Gen 1 plugin archive, Gen 2 portable app) and how they inform STLT-Rewired.

## Inputs inspected

### Gen1 plugin archive

Path:

```text
C:\Users\sened\Downloads\ltsteamplugin-main.zip
```

Observed:

- Millennium plugin archive.
- `plugin.json`:
  - `name`: `luatools`
  - `common_name`: `LuaTools`
  - `version`: `9.0.1`
  - `backendType`: `lua`
- compact layout:
  - `backend/main.lua`
  - `backend/paths.lua`
  - `backend/plugin_logger.lua`
  - `backend/steam_utils.lua`
  - `public/luatools.js`
  - themes
  - deploy/sync/locale scripts
- about 14 backend RPC functions.
- about 24 frontend backend-call sites.

Interpretation:

Gen1 is useful as a small reference implementation for the official plugin contract, not as the final product scope. It is much smaller than STLT-Rewired and does not contain the broader augmentation set.

### Gen2 portable app

Local reference (optional, typically in a **private** dev checkout — not committed to STLT-Rewired):

```text
E:\LuaTools-win-Portable
```

Observed:
- `current/sq.version` identifies:
  - app id: `LuaTools`
  - version: `1.2.2` (public notes; newer builds may differ)
  - runtime dependency: `net8-x64-desktop`
- key binaries:
  - `LuaTools.exe`
  - `current/LuaTools.exe`
  - `current/LuaTools.dll`
- discovered service/class names from `LuaTools.dll` strings:
  - `LuaToolsGui`
  - `LuaToolsApiClient`
  - `PluginInstallerService`
  - `CefInjectorService`
  - `HubcapService`
  - `GithubProxy`
  - `SteamAppInfoCache`
  - `HardwareAppIdService`
  - `CloudRedirectService`
  - `SteamlessService`
  - `UnlockerService`
  - `DenuvoFixes` / `DenuvoListings` / `DownloadDenuvo`

Interpretation:

Gen2 is a richer desktop app model. It appears to manage plugin install/update/injection and broad Steam/LuaTools workflows from a WPF shell. It should be treated as a UX/service reference, not as code to copy directly into the Millennium plugin. Without source, only behavior/strings/installed files can be inspected safely.

### STLT-Rewired

Path:

```text
F:\STLT-Rewired
```

Observed:

- Millennium Lua plugin, drop-in name `luatools`.
- no Python HTTP bridge.
- native Millennium 3.x backend/frontend IPC.
- 39 backend Lua modules.
- 169 exported backend functions.
- about 100 unique frontend RPC methods.
- includes Ryuu Premium session handling, Ryuu catalog, fixes fallback/hardening, diagnostics, backup, sync, key vault, achievements, workshop, batch, profiles, account/userdata tools, deploy hardening.

Interpretation:

STLT-Rewired is already closer to a feature lab / power-user fork than to Gen1. Gen2 has product ideas worth matching, but the implementation should be clean-room where possible and adapted to the plugin architecture.

## Comparison table

| Area | Gen1 plugin | Gen2 portable app | STLT-Rewired |
| --- | --- | --- | --- |
| Runtime | Millennium Lua plugin | Windows .NET/WPF app | Millennium Lua plugin |
| Primary UI | Steam injected JS | Desktop WPF | Steam injected JS |
| Backend | Lua | .NET services | Lua modules |
| IPC | Millennium callServerMethod | app services / possible CEF bridge | Millennium callServerMethod |
| Scope | compact add/fixes/settings | full app manager | broad in-Steam augmentation fork |
| Ryuu | limited/unknown | not confirmed from strings | Ryuu Premium source + catalog/fixes |
| Fixes | basic | Denuvo/fixes services visible | safe fixes flow + Ryuu fallback |
| CloudRedirect | not apparent | service visible | explicit external/manual integration only |
| Steamless/unlocker | not apparent | services visible | not silently integrated |
| Deploy | simple scripts | app updater/installer | backup-preserving deploy.ps1 |

## Useful things to take from Gen2

Do not copy binaries or hidden code. Use these as product requirements and implement our own clean version:

1. Desktop shell — **Rewired Manager** (`manager/`) is our app for plugin deploy, Ryuu auth, source status, backup/restore, and diagnostics.

2. Plugin installer/updater
   - Gen2 has `PluginInstallerService` and `CefInjectorService` concepts.
   - Rewired should have a clean installer that deploys Millennium plugin files, preserves secrets, checks Millennium version, and can roll back.

3. Hubcap/Morrenus UX
   - Gen2 has `HubcapService`, key validation, usage stats, source badges.
   - Rewired already has Morrenus/Ryuu backend pieces; UI can be made more first-class.

4. Denuvo/fixes UX
   - Gen2 has Denuvo listing/fix/download names.
   - Rewired fixes module should expose safer, source-attributed fix metadata and an audit trail.

5. CloudRedirect/Steam cloud flow
   - Gen2 exposes CloudRedirect management.
   - Rewired should not silently patch; it can detect cloud errors and launch/guide CloudRedirect as an explicit action.

6. Hardware app id / app info cache
   - Gen2 has hardware app ID and Steam app info caching concepts.
   - Rewired can add better app metadata caching for faster source/filter/fixes panels.

## Things not to import blindly

- any secret storage defaults;
- any closed/binary implementation details;
- silent SteamTools/OpenSteamTools/CloudRedirect patch flows;
- anything requiring background daemons without user consent;
- product logic that assumes a desktop app when the feature belongs in Steam's webkit plugin.

## Recommended direction

Build an independent two-layer product:

1. `STLT-Rewired` plugin:
   - in-Steam UI;
   - source/Ryuu/fixes/add flow;
   - diagnostics and per-game maintenance;
   - no daemon.

2. **Rewired Manager** desktop app (`manager/`):
   - installer/updater/rollback;
   - Ryuu account/session helper;
   - source health dashboard;
   - CloudRedirect launcher/assistant;
   - richer logs and diagnostics export.

This lets Rewired keep the Steam UX while still matching Gen2's “app” convenience where a native app is genuinely better.
