# Rewired Manager

**Our** Windows desktop app for STLT-Rewired — same project, same repo as the Millennium plugin.

Rewired Manager handles what is awkward inside Steam webkit: secrets, deploy/rollback, source health probes, and diagnostic exports. The in-Steam plugin stays the primary UX for add/fixes/play.

## Layout (this repo)

```text
manager/
  src/RewiredManager.Core/     # PluginLocator, SecretsStore
  docs/
    REWIRED_MANAGER_ARCHITECTURE.md
  README.md
```

Plugin: `backend/`, `public/` at repo root. Shared secrets: `backend/data/secrets.local.json`.

## MVP

1. Detect live STLT-Rewired plugin install.
2. Read/write Ryuu + ManifestHub secrets (never log values).
3. Validate ManifestHub key and Ryuu session.
4. Source health dashboard.
5. Deploy/rollback (C# port of `deploy.ps1`).
6. Redacted diagnostics bundle export.

## Build

```powershell
winget install Microsoft.DotNet.SDK.8
```

See [docs/REWIRED_MANAGER_ARCHITECTURE.md](docs/REWIRED_MANAGER_ARCHITECTURE.md) and [../docs/REWIRED_MANAGER_PLAN.md](../docs/REWIRED_MANAGER_PLAN.md).
