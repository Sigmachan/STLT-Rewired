# Installers

One-shot setup scripts. Dev/build tools live under `scripts/` — not here.

## Short one-liners (preferred)

Short domain (`sigmachan.ru` → jsDelivr):

| | Command |
|--|---------|
| **Windows AIO** | `irm https://sigmachan.ru/install.ps1 \| iex` |
| **Windows update** | `irm https://sigmachan.ru/update.ps1 \| iex` |
| **Linux AIO** | `curl -fsSL https://sigmachan.ru/install \| bash` |
| **Linux update** | `curl -fsSL https://sigmachan.ru/update \| bash` |

Root files `install.sh`, `install.ps1`, `update.sh`, `update.ps1` are thin wrappers around the scripts below.

## Scripts in this folder

| Script | Platform | What it installs |
|--------|----------|------------------|
| `Windows.ps1` | Windows | AIO: Millennium (if needed) + OpenSteamTool + Rewired plugin (`-SkipOpenSteamTool` to omit unlock) |
| `Windows-Update.ps1` | Windows | Plugin update from latest GitHub release |
| `Linux.sh` | Linux | AIO: ACCELA + SLSsteam + Millennium (if needed) + Rewired plugin |
| `Linux-Update.sh` | Linux | Plugin update (skips Millennium + unlock) |
| `Linux-Unlock.sh` | Linux | ACCELA + SLSsteam only (rare) |
| `lib/` | — | Shared helpers (`Rewired.Install.psm1`) |

## Local checkout

```powershell
pwsh -NoProfile -File install/Windows.ps1 -FromRepo
```
```bash
bash install/Linux.sh
```
