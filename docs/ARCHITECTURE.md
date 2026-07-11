# STLT-Rewired architecture

STLT-Rewired is a Windows-first Millennium 3.x plugin with a Lua backend and a bundled Steam webkit frontend. It intentionally avoids the old detached Python/local HTTP bridge pattern.

## Runtime shape

```text
Steam web page / Store DOM
  -> public/luatools.js
  -> Millennium.callServerMethod('luatools', 'PascalCaseMethod', payload)
  -> global Lua function in backend/main.lua
  -> backend module under backend/*.lua
  -> JSON-safe response back to frontend
```

Important constraints:

- plugin name is `luatools` for drop-in compatibility with existing Millennium config and frontend calls.
- backend type is Lua.
- all user credentials stay in ignored local files, primarily `backend/data/secrets.local.json`.
- frontend changes must be rebuilt into `.millennium/Dist/webkit.js` with `scripts/build_webkit_bundle.py`.
- deploy preserves `backend/data/` and writes backups outside `millennium/plugins/` to avoid duplicate plugin-name collisions.

## Repository layout

```text
plugin.json                  Millennium plugin metadata
backend/main.lua             exported RPC functions and orchestration
backend/*.lua                feature modules
backend/api.json             source list
backend/data/                local runtime state/secrets; mostly ignored
public/luatools.js           injected Steam UI
public/themes/               theme assets
.millennium/Dist/webkit.js   built/embedded frontend bundle
scripts/                     build/validation helpers
deploy.ps1                   Windows deploy/restore/runtime update script
docs/                        project documentation and collaboration notes
```

## Backend modules

Current backend modules include:

- source/download path: `api_manifest.lua`, `custom_apis.lua`, `downloads.lua`, `source_chain.lua`, `history.lua`, `ryuu.lua`.
- fixes path: `fixes.lua`.
- Steam/library management: `steam_utils.lua`, `steam_version.lua`, `manifests.lua`, `acf_lock.lua`, `cache_tools.lua`.
- diagnostics/health: `health.lua`, `diagnostics.lua`, `plugin_logger.lua`.
- user data and cloud-adjacent tools: `cloud_fix.lua`, `sync.lua`, `account.lua`.
- augmentations: `backup.lua`, `batch.lua`, `workshop.lua`, `achievements.lua`, `dlc.lua`, `key_vault.lua`, `profiles.lua`, `tokeer.lua`, `mods.lua`, `sentinel.lua`, `crack_migrator.lua`, `config_transfer.lua`.

## RPC surface

`backend/main.lua` exports more than 160 global functions. The frontend currently calls about 100 unique backend methods.

High-value groups:

### Core activation and sources

- `StartAddViaLuaTools`
- `GetAddViaLuaToolsStatus`
- `CancelAddViaLuaTools`
- `CheckApisForApp`
- `StartAddViaLuaToolsFromUrl`
- `StartDownloadNoRestart`
- `AutoFinalizeActivation`
- `GetApiList`
- `GetAllApis`
- `AddCustomApi`
- `ToggleApi`
- `RemoveApi`
- `ReorderApis`

### Ryuu / Morrenus / catalog

- `GetRyuuSession`
- `SearchRyuuCatalog`
- `GetMorrenusStats`
- `FetchFreeApisNow`
- `GetSourceChain`
- `SaveSourceChain`

### Fixes

- `CheckForFixes`
- `ApplyGameFix`
- `GetApplyFixStatus`
- `CancelApplyFix`
- `GetInstalledFixes`
- `UnFixGame`
- `UninstallFix`
- `GetUnfixStatus`

### Maintenance and diagnostics

- `GetMillenniumHealth`
- `DiagnoseApp`
- `ExportDiagnosticReport`
- `GetQuickDashboard`
- `ScanSteamLibraries`
- `GetSteamProcessInfo`
- `GetCacheInfo`
- `CleanSteamCache`

### Augmented STLT-style panels

- backup/restore: `CreateBackup`, `ListBackups`, `RestoreBackup`, `DeleteBackup`.
- workshop: `ListWorkshopSubscribed`, `DownloadWorkshopItem`, `DeleteWorkshopItem`.
- achievements: `GetAchievementInfo`, `SeedAchievementFiles`, `GetAchievementProgress`, `ListAchievementWatchlist`.
- userdata/account tools: `ListUserdataAccounts`, `InspectGameUserdata`, `TransferGameUserdata`, `ExtractLoginTokens`, `SwitchToAccount`.
- sync: `GetSyncConfig`, `SetSyncConfig`, `SyncPush`, `SyncPull`, `SyncStatus`, `SyncTestConnection`.
- key/profile tools: `ListKeyProfiles`, `SaveKeyProfile`, `LoadKeyProfile`, `ExportKeyProfile`, `ImportKeyProfile`, `ListProfilesFor`, `SaveProfile`, `ActivateProfile`.
- batch: `StartBatchDownload`, `GetBatchStatus`, `CancelBatch`, `PauseBatch`, `ResumeBatch`.

## Safety model

### Secrets

Local secrets are read from:

```text
backend/data/secrets.local.json
```

Known keys:

```json
{
  "ryuuSession": "<Ryuu Cookie header>",
  "morrenusApiKey": "<Morrenus API key>"
}
```

This file is ignored and preserved across deploys. Never print or commit it.

### Fix archives

Downloaded fix archives are validated before extraction:

- no rooted paths;
- no drive prefixes;
- no `:`;
- no `..` path segments;
- state JSON is BOM-free ASCII;
- System32 `tar.exe` / `curl.exe` are preferred over MSYS PATH resolution.

### Deploy

`deploy.ps1`:

- builds webkit before copying;
- backs up live plugin outside `plugins/`;
- preserves `backend/data/`;
- can restore latest backup;
- validates Millennium beta runtime archive layout;
- avoids runtime replacement while Steam is running.

## Development rules

1. Trace both frontend call and backend RPC before changing contracts.
2. If editing `public/luatools.js`, rebuild `.millennium/Dist/webkit.js`.
3. If adding a credential/source, use local secrets or settings, never committed defaults.
4. Verify risky changes with a temp `hermes-verify-*` ad-hoc script and state that it is ad-hoc verification, not a full test suite.
5. Deploy and read back live files when validating in Steam.
