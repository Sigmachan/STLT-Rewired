# Rewired Manager

Windows desktop companion for [STLT-Rewired](https://github.com/Sigmachan/STLT-Rewired). Optional — the Millennium plugin works standalone.

## Requirements

- .NET 8 SDK (`dotnet --version` ≥ 8.0)
- Windows 10/11
- Steam + Rewired plugin deployed to `millennium/plugins/luatools`

## Build

```powershell
cd manager
dotnet build RewiredManager.sln -c Release
dotnet run --project src/RewiredManager/RewiredManager.csproj -c Release
```

Published exe:

```powershell
dotnet publish src/RewiredManager/RewiredManager.csproj -c Release -r win-x64 --self-contained false -o ../../releases/RewiredManager
```

## MVP (current)

- Detect Steam + live plugin (`PluginLocator`)
- Show plugin version / secrets configured badges (`SecretsStore`)
- Test + save ManifestHub API key (`ManifestHubClient`)

## Next

- Ryuu session probe + catalog smoke
- Source health grid
- Invoke `deploy.ps1` with backup/restore
- Redacted diagnostics export

See [docs/REWIRED_MANAGER_ARCHITECTURE.md](docs/REWIRED_MANAGER_ARCHITECTURE.md).
