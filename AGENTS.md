# AGENTS.md

STLT-Rewired is a **Steam Millennium 3.x Lua plugin** (LuaTools rebuilt on the piqseu
base). The backend is Lua under `backend/` (RPC = PascalCase global functions dispatched
via Millennium `callServerMethod`); the frontend is a single bundle `public/luatools.js`
embedded into `.millennium/Dist/webkit.js`. See `readme.md`, `REWIRED-PLAN.md`, and
`docs/ARCHITECTURE.md` for the full picture. `backend/AGENTS.md` covers backend scope.

## Cursor Cloud specific instructions

### What can and cannot run here
- The **live plugin cannot run in a cloud/headless Linux VM**. It only runs inside a real
  Steam desktop client with Millennium 3.x (Windows, or Linux via SLSsteam/ACCELA). Do
  **not** try to launch Steam, `deploy.ps1`, `install/Windows.ps1`, or `install/Linux.sh`
  here — they are Windows-PowerShell / live-Steam only.
- On a real Linux Steam desktop the plugin is supported. `install/Linux.sh` installs
  ACCELA + SLSsteam via enter-the-wired, then Millennium + plugin. Unlock-only:
  `install/Linux-Unlock.sh`. Shared config: `~/.local/share/Rewired/rewired.json`.
  OpenSteamTool is Windows-only.
- The runnable dev surface in cloud is: the Python build/validate/test scripts (`scripts/`,
  stdlib only — no pip deps, no `requirements.txt`/`package.json`), a Node syntax check of
  the frontend bundle, and Lua 5.4 static + logic checks of `backend/`.

### Tooling
- `python3` (3.12) and `node` (22) are in the base image.
- `lua5.4`, `luarocks`, and `luacheck` are provided by the VM snapshot. If ever missing:
  `sudo apt-get install -y lua5.4 luarocks && sudo luarocks install luacheck`.

### Commands
- Build (embed frontend into webkit bundle; run after editing `public/luatools.js`):
  `python3 scripts/build_webkit_bundle.py`
- Tests: `python3 scripts/test_github_mirror.py`
- Locale sync — **NOT a pass/fail test; it MUTATES `backend/locales/*.json`** by adding
  keys found in `public/luatools.js`. Run `python3 scripts/validate_locales.py` only when
  intentionally syncing locales; otherwise revert with `git checkout -- backend/locales/`.
- Frontend syntax check: `node --check public/luatools.js`
- Lua syntax check (prefer `lua5.4` over `luacheck` — the installed luacheck is built on
  Lua 5.1 and misflags valid 5.4 syntax):
  `for f in $(find backend -name '*.lua'); do lua5.4 -e "assert(loadfile('$f'))"; done`
- Run a backend module standalone: set `package.path="backend/?.lua;"..package.path` and
  stub the Millennium-provided modules via `package.preload` (`logger`, `http`, `fs`,
  `utils`, `json`, `millennium`) before `require`-ing the module. Pure-logic modules like
  `github_mirror` only need a `logger` stub.

> Note: root `AGENTS.md` is listed in `.gitignore` (intended as local-only). This file was
> force-added so future cloud agents inherit these notes; merge it to keep them.
