# Installers

One-shot setup scripts. Dev/build tools live under `scripts/` — not here.

## Short one-liners (preferred)

Short domain (`sigmachan.ru` → jsDelivr):

| | Command |
|--|---------|
| **Windows install** | `irm https://sigmachan.ru/install.ps1 \| iex` |
| **Windows update** | `irm https://sigmachan.ru/update.ps1 \| iex` |
| **Linux install** | `curl -fsSL https://sigmachan.ru/install \| bash` |
| **Linux update** | `curl -fsSL https://sigmachan.ru/update \| bash` |
| **Linux unlock only** | `curl -fsSL https://sigmachan.ru/unlock \| bash` |

Root files `install.sh`, `install.ps1`, `update.sh`, `update.ps1`, `unlock.sh` are thin wrappers around the scripts below.
(Cloudflare pretty paths `/install` `/update` `/unlock` redirect to the `.sh` files.)

## Scripts in this folder

| Script | Platform | What it installs |
|--------|----------|------------------|
| `Windows.ps1` | Windows | Millennium (if needed) + Rewired plugin (+ OpenSteamTool only with `-InstallOpenSteamTool` if enabled) |
| `Windows-Update.ps1` | Windows | Plugin update from latest GitHub release |
| `Linux.sh` | Linux | ACCELA + SLSsteam + Millennium (if needed) + Rewired plugin |
| `Linux-Update.sh` | Linux | Plugin update (skips Millennium + unlock) |
| `Linux-Unlock.sh` | Linux | ACCELA + SLSsteam only |
| `lib/` | — | Shared helpers (`Rewired.Install.psm1`) |

## Local checkout

```powershell
pwsh -NoProfile -File install/Windows.ps1 -FromRepo
```
```bash
bash install/Linux.sh
```
