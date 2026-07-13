# Gen2 → Rewired parity map

Reference notes from LuaTools v1.2.x portable app + Hermes/decompiled clean-room analysis. **Do not copy decompiled C# into Rewired.**

Local-only decompile: `docs/gen2/decompiled/` (gitignored). Hermes references: `%LOCALAPPDATA%\hermes\skills\millennium-plugin-development\references\`.

## Architecture comparison

| Gen2 (`LuaToolsGui`) | Rewired equivalent | Status |
| --- | --- | --- |
| WPF desktop shell | `Rewired.exe` (`manager/`) | **Done** — Material You sidebar IA (Home/Add/Manage/Mode/Fixes/Plugin/Settings) |
| `PluginInstallerService` | `PluginDeployService` + `deploy.ps1` + backup restore | Done |
| `CefInjectorService` | Millennium native `webkit.js` | Intentional skip |
| `HttpServerService` (:8080 bridge) | In-Steam Ryuu add + Manager | Done (no localhost bridge) |
| `UnlockerService` | `UnlockBackendService` + Mode tab | Done |
| `CloudRedirectService` | `CloudRedirectAssistantService` | Done — explicit launch |
| `HubcapService` | Plugin settings + Manager Hubcap stats + source probe | Done |
| `LuaToolsApiClient` | `backend/ryuu.lua` + Manager `RyuuCatalogService` | Done (Ryuu-first; Gen2 used `167.235.229.108`) |
| `SteamAppInfoCache` | Steam store search in catalog | Partial |
| `AuthService` | Local secrets only | N/A |
| `SteamlessService` | Guide / policy only | Guide only |
| Velopack updater | `ManagerUpdateService` | Done |

## Manager feature matrix

| Feature | Status |
| --- | --- |
| Home dashboard + Launch Steam | Done |
| Add: catalog search, AppID, local file | Done |
| Manage: list, remove, open folders | Done |
| Mode: OST install, backend picker, CloudRedirect | Done |
| Fixes: in-Steam guide + Ryuu fixes test | Done |
| Plugin: inspect, probe, deploy, restore backup | Done |
| Settings: secrets, Hubcap stats, diagnostics export | Done |
| Footer: Rewired + Millennium version | Done |
| Desktop fix browser / apply | Deferred — in-Steam Fixes panel |
| `cloud_log.txt` parser | **Done** — Manager Mode tab scan |
| SteamTools silent install | Will not port |

## In-Steam plugin

| Feature | Status |
| --- | --- |
| Source Health / Companion / Support Bundle panels | Done |
| Ryuu catalog panel | Done |
| Config import/export (Settings) | Done |
| ManifestHub usage stats button | Done |
| Menu locale keys (en/ru) | Done — uk/de/be/ru complete |
| Key vault / sync / config persistence | Fixed — `apply_settings_changes` + secrets.local.json |
| Global RPC payload parse | Done — all `luatools` calls unwrap bridge envelopes |
| Ryuu catalog warm | Async background load + UI polling (no Steam freeze) |
| Theme-token sweep (hardcoded grays) | Done — advanced overlays use theme tokens |
| Denuvo in-app browser | Ryuu fixes fallback only |

## Do not port

- CefInjector / `127.0.0.1:6767` RPC hijack
- Closed Gen2 endpoints (`167.235.229.108/check_apis`)
- Silent SteamTools/CloudRedirect patching
- Supabase auth, tray daemon, analytics

## Reference map

| Location | Contents |
| --- | --- |
| `F:\STLT-Rewired\docs\gen2\decompiled\` | ~153 C# files from `LuaTools.dll` |
| `F:\Rewired-Manager-Reference\` | `LUATOOLS_GEN2_REFERENCE.md`, `LUATOOLS_GEN2_REVERSE.md` |
| `%LOCALAPPDATA%\hermes\skills\...\references\` | Ryuu catalog, fixes, CloudRedirect, Gen1/Gen2 notes |
| `E:\LuaTools-win-Portable` | Live Gen2 portable binary |
