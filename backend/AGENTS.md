## Backend scope

Millennium 3.x Lua plugin. RPC exports in `main.lua` (PascalCase globals).

- Settings: `data/settings.json`
- Secrets: `data/secrets.local.json` (gitignored)
- Unlock paths: `unlock_paths.lua` (OpenSteamTool `config/lua` vs `config/stplug-in`)

Heavy RPC must stay serialized from frontend — see `public/luatools.js` `HEAVY_RPC` set.
