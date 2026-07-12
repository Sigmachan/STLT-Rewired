# Rewired Manager architecture

**Rewired Manager** — our .NET 8 WPF desktop app, developed in `manager/` alongside the plugin.
No localhost CEF bridge; no dependency on upstream desktop apps.

## Goals

- Make setup, secrets, deploy, and diagnostics **easy** without replacing Millennium IPC.
- Windows-first, .NET 8 WPF, WPF-UI shell.
- No required background daemon; tray optional.

## Solution layout (planned)

```text
manager/
  src/
    RewiredManager/                 # WPF host (WPF-UI NavigationView)
    RewiredManager.Core/            # Steam paths, secrets IO, plugin detection
    RewiredManager.Services/        # ManifestHub, Ryuu, source probes, deploy
  docs/
  RewiredManager.sln
```

## Core services (MVP)

### `PluginLocator`

- Resolve Steam root (registry + `steam.exe` probe).
- Resolve `{Steam}/millennium/plugins/luatools`.
- Read `plugin.json` version / `common_name`.
- Detect duplicate `luatools` plugin folders (same logic as `deploy.ps1`).

### `SecretsStore`

- Read/write `{plugin}/backend/data/secrets.local.json`.
- Keys: `ryuuSession`, `morrenusApiKey` (ManifestHub).
- Never log secret values; mask in UI (`••••••••` + “configured” badge).
- Optional: DPAPI-protect manager-side copy (`RewiredManager.Core`).

### `ManifestHubService`

- Format check: `smm_` + 96 hex (match `backend/manifesthub.lua`).
- Live validate: `GET hubcapmanifest.com/api/v1/user/stats?api_key=…`
- Surface username, daily usage/limit in Settings page.

### `RyuuService`

- Session probe: `generator.ryuu.lol/api/check_session` (cookie header only in memory).
- Catalog search: paginated `api/games?limit=&page=&search=` (same as `backend/ryuu.lua`).
- Never persist cookie outside `secrets.local.json` unless user saves.

### `SourceHealthService`

- Probe endpoints from plugin `api.json` + fixed list (Ryuu, ManifestHub, GitHub raw).
- Classify: ok / warn / offline / auth-required.
- Reuse redaction rules from `feature_parity.lua` for any logged URLs.

### `PluginDeployService`

- Port `deploy.ps1` behavior:
  - backup to `{Steam}/millennium/_plugin-backups/luatools.backup-*`
  - preserve `backend/data`
  - copy allowlist: `backend`, `public`, `.millennium`, `plugin.json`
  - dedupe duplicate plugin folders
- Preflight: warn if Steam running; require confirm before restart.

### `DiagnosticsService`

- Collect: plugin version, Millennium version (if detectable), source health summary, last deploy backup path.
- Redact secrets; export zip for support.

## UI pages (MVP)

| Page | Purpose |
| --- | --- |
| Home | Plugin detected? version? Steam path? quick health |
| Ryuu | Session status, test, catalog search smoke |
| ManifestHub | Key entry, test, stats |
| Sources | Health grid |
| Plugin | Install/update from GitHub release, backup/restore |
| Diagnostics | Export redacted bundle |

## Data files (shared with plugin)

```json
// backend/data/secrets.local.json (gitignored on dev machines)
{
  "ryuuSession": "<cookie>",
  "morrenusApiKey": "smm_..."
}
```

```json
// backend/data/settings.json
{
  "version": 1,
  "values": { "general": { "language": "en", ... } }
}
```

Manager edits secrets; plugin reads them via `settings/manager.lua`.

## Explicit non-goals (v1)

- `CefInjectorService` equivalent.
- Python HTTP bridge on localhost.
- Silent CloudRedirect / Steamless / unlocker patching.
- Discord OAuth requirement.

## Build prerequisites

```powershell
winget install Microsoft.DotNet.SDK.8
cd F:\STLT-Rewired\manager
dotnet new sln -n RewiredManager
# projects added when skeleton is scaffolded
```

## Next implementation step

1. Scaffold `RewiredManager.sln` + `RewiredManager.Core` with `PluginLocator` + `SecretsStore`.
2. WPF shell with Home + Settings (ManifestHub test only).
3. Wire deploy actions to embedded C# port of `deploy.ps1`.
