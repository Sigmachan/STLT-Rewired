## Learned User Preferences

- Work on `main` only unless explicitly asked to use a feature branch.
- Commit and push only when explicitly requested.
- Do not add Cursor `Co-authored-by` / `cursoragent` trailers to commits.
- Do not mention reverse engineering or competitive teardown in public commit messages or changelog.
- Only competitive reverse-engineering docs belong in a private repo; all Rewired product code stays in STLT-Rewired.
- Rewired Manager is our own first-class desktop app, not a third-party companion or research artifact.
- User authorizes routine implementation decisions without asking first.
- Supported locale packs: American English (`en`), Deutsch (`de`), Русский (`ru`), Ukrainian (`uk`), Belarusian (`be`).
- Exclude `.cursor/` and unrelated files from commits.

## Learned Workspace Facts

- STLT-Rewired is a Windows-first Millennium `luatools` plugin with a native Lua backend (Rewired branding).
- Live plugin deploy path: `C:\Program Files (x86)\Steam\millennium\plugins\luatools` via `deploy.ps1`.
- Run PowerShell scripts with `pwsh -NoProfile -File` because the user's PowerShell profile adds startup delay.
- Rewired Manager lives in `manager/` in the same repo as the plugin.
- OpenSteamTool unlock backend uses `config/lua` for installed lua scripts, not always `stplug-in`.
- Local reference repos: `F:\STLT` (prior STLT fork), `F:\Rewired-Manager-Reference` (private research docs only).
- User's Steam runs Millennium v3.4.0-beta.8 on Windows.
- Ryuu catalog search must stay bounded (max ~3 paginated pages, short timeouts) to avoid freezing Steam.
- Opening Settings previously crashed Millennium beta.8 from stacked heavy RPC; serialize/defer `GetInstalledFixes`, `GetInstalledLuaScripts`, and manifest auto-update.
- ManifestHub (Morrenus) is the manifest hub name/key used in settings.
- `scripts/smoke_deploy.ps1` validates the live installed plugin tree.
- Upstream thin plugin reference: https://github.com/madoiscool/ltsteamplugin
