# Rewired Manager

Windows desktop companion for **STLT-Rewired** (the `luatools` Millennium plugin).  
Lives in this repo under `manager/` — same product, one GitHub repo, one release page.

The plugin works standalone. The manager helps with plugin discovery, source health probes, and (later) deploy/rollback and secrets UX.

## Requirements

- .NET 8 SDK
- Windows 10/11
- Steam + Rewired deployed to `{Steam}\millennium\plugins\luatools`

## Build & run (dev)

```powershell
cd F:\STLT-Rewired\manager
F:\dotnet-sdk\dotnet.exe build RewiredManager.sln -c Release
F:\dotnet-sdk\dotnet.exe run --project RewiredManager.App -c Release
```

Or if `dotnet` is on PATH:

```powershell
dotnet run --project RewiredManager.App -c Release
```

## Publish release zip

Output: `releases/RewiredManager-win-x64-framework-dependent.zip` (needs [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) on the target PC).

```powershell
pwsh -NoProfile -File F:\STLT-Rewired\manager\scripts\publish-manager.ps1
```

Ship both artifacts on the same GitHub release as the plugin:

| Asset | Purpose |
|-------|---------|
| `STLT-Rewired.zip` | Millennium plugin (`scripts/build_release.ps1`) |
| `RewiredManager-win-x64-framework-dependent.zip` | Desktop manager |

## Current features

- Inspect live plugin path (version, backend, webkit bundle, secrets present/missing)
- Probe Ryuu catalog/fixes, LuaTools fixes index, GitHub reachability
- Never prints cookie or API key values

## Layout

```text
manager/
  RewiredManager.sln
  RewiredManager.App/     WPF shell + services
  scripts/publish-manager.ps1
  docs/REWIRED_MANAGER_ARCHITECTURE.md
```

## Deprecated external repos

`Sigmachan/Rewired-Manager` and `Sigmachan/Rewired-Manager-Binaries` are superseded by this tree. Archive or delete them after cutting a combined STLT-Rewired release that includes the manager zip.
