# Installers

One-shot setup scripts. Dev/build tools live under `scripts/` — not here.

| Script | Platform | What it installs |
|--------|----------|------------------|
| `Windows.ps1` | Windows | Millennium (if needed) + Rewired plugin (+ OpenSteamTool only with `-InstallOpenSteamTool`) |
| `Windows-Update.ps1` | Windows | Plugin update from latest GitHub release |
| `Linux.sh` | Linux | ACCELA + SLSsteam + Millennium (if needed) + Rewired plugin |
| `Linux-Update.sh` | Linux | Plugin update (skips Millennium + unlock) |
| `Linux-Unlock.sh` | Linux | ACCELA + SLSsteam only |
| `lib/` | — | Shared helpers (`Rewired.Install.psm1`) |

## One-liners

**Windows**
```powershell
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows.ps1 | iex
irm https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Windows-Update.ps1 | iex
```

**Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh | bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Update.sh | bash
curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Unlock.sh | bash
```

## Local checkout
```powershell
pwsh -NoProfile -File install/Windows.ps1 -FromRepo
```
```bash
bash install/Linux.sh
```

Old `scripts/install.*` URLs still work — they forward here.
