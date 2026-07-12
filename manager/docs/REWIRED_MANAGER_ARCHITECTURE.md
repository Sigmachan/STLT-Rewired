# Rewired Manager architecture

**Rewired Manager** — .NET 8 WPF desktop app in `manager/` (same repo as the `luatools` plugin).  
No localhost CEF bridge; no separate source/binary GitHub repos.

## Goals

- Plugin discovery, source health, secrets status without replacing Millennium IPC.
- Windows-first, optional companion (not a daemon).
- Release zip ships on the same GitHub release as `STLT-Rewired.zip`.

## Solution layout (current)

```text
manager/
  RewiredManager.sln
  RewiredManager.App/
    MainWindow.xaml          # inspect + probe UI
    Services/
      PluginDiscoveryService.cs
      SecretStoreService.cs
      SourceHealthService.cs
    Models/
  scripts/publish-manager.ps1
  docs/
```

## Services

### `PluginDiscoveryService`

- Default path: `{ProgramFilesX86}\Steam\millennium\plugins\luatools`
- Reads `plugin.json` version / `common_name`
- Checks backend, webkit bundle, secrets file presence

### `SecretStoreService`

- Reads `{plugin}/backend/data/secrets.local.json`
- Reports Ryuu session / ManifestHub key as present/missing only
- Supplies cookie header in-memory for Ryuu probes (never logged)

### `SourceHealthService`

- Probes Ryuu catalog/fixes, LuaTools fixes index, GitHub
- Classifies OK/FAIL with HTTP status and latency

## Planned (not in UI yet)

- ManifestHub key test + save (port from plugin settings flow)
- Invoke `deploy.ps1` with backup/restore preflight
- Redacted diagnostics export zip

## Data files (shared with plugin)

```json
// backend/data/secrets.local.json (gitignored)
{
  "ryuuSession": "<cookie>",
  "morrenusApiKey": "smm_..."
}
```

Manager reads/writes the **live plugin** copy under Steam, not the git checkout.

## Build / publish

```powershell
pwsh -NoProfile -File manager/scripts/publish-manager.ps1
```

Output: `releases/RewiredManager-win-x64-framework-dependent.zip`

## Deprecated

`Sigmachan/Rewired-Manager` and `Sigmachan/Rewired-Manager-Binaries` — archive after first combined STLT-Rewired release includes the manager zip.
