# Installers

One-shot setup scripts. Dev/build tools live under `scripts/` — not here.

## Short one-liners (preferred)

jsDelivr CDN (shorter than raw GitHub):

| | Command |
|--|---------|
| **Windows install** | `irm https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/i.ps1 \| iex` |
| **Windows update** | `irm https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/u.ps1 \| iex` |
| **Linux install** | `curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/i \| bash` |
| **Linux update** | `curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/u \| bash` |
| **Linux unlock only** | `curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/unlock \| bash` |

Root files `i`, `i.ps1`, `u`, `u.ps1`, `unlock` are thin wrappers around the scripts below.

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
