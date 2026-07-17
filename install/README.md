# Installers

One-shot setup scripts. Dev/build tools live under `scripts/` — not here.

## Short one-liners (preferred)

Short domain (`sigmachan.ru` → jsDelivr):

| | Command |
|--|---------|
| **Windows AIO** | `irm https://sigmachan.ru/install.ps1 \| iex` |
| **Linux AIO** | `curl -fsSL https://sigmachan.ru/install \| bash` |

Re-run the same command to update. (`update` / `update.ps1` are aliases of install.)

Root files `install.sh` / `install.ps1` wrap the scripts below.

## Scripts in this folder

| Script | Platform | What it installs |
|--------|----------|------------------|
| `Windows.ps1` | Windows | AIO: Millennium (if needed) + OpenSteamTool (if needed) + Rewired plugin |
| `Windows-Update.ps1` | Windows | Alias of `Windows.ps1` |
| `Linux.sh` | Linux | AIO: ACCELA + SLSsteam + Millennium (if needed) + Rewired plugin |
| `Linux-Update.sh` | Linux | Alias of `Linux.sh` |
| `Linux-Unlock.sh` | Linux | ACCELA + SLSsteam only (rare) |
| `lib/` | — | Shared helpers (`Rewired.Install.psm1`) |

## Local checkout

```powershell
pwsh -NoProfile -File install/Windows.ps1 -FromRepo
```
```bash
bash install/Linux.sh
```
