# STLT — Rewired

LuaTools rebuilt on the **modern Millennium 3.x** plugin model, so it actually works
on current Millennium (current target: 3.4.0-beta.8). Base is the maintained upstream
**piqseu/ltsteamplugin** (Lua backend + native `callServerMethod` IPC); STLT's
extra features get ported in on top.

## Why this exists

STLT (the 10.2.4 fork) was built for Millennium **3.0.0-beta.26** and used the old
model: a hand-injected 9.5k-line `luatools.js` **plus a detached Python HTTP server
on `:38495`** that **overrode `Millennium.callServerMethod`**. On modern Millennium 3.x
that override detonates inside the store webkit → "broke the store", no Add button.

The upstream never did that: **frontend → native `Millennium.callServerMethod` →
global Lua function → returns a `cjson` string.** No Python, no bridge, no port.
Rewired adopts that model wholesale.

## Architecture (locked)

- `plugin.json`: `backendType: lua`, `name: luatools` (drop-in; matches the frontend's
  hardcoded plugin arg and your existing `enabledPlugins`), `common_name: "STLT - Rewired"`.
- `backend/*.lua`: each IPC method is a **global Lua function** returning `cjson.encode(...)`.
  Lua APIs: `require("http"|"fs"|"json"|"utils")` + Millennium's `millennium`/`logger`.
- `backend/main.lua`: `copy_webkit_files()` + `add_browser_js("webkit/luatools.js")`;
  `_G["Logger.log"]` for frontend logging.
- Frontend `public/luatools.js`: calls `callServerMethod("luatools", "Method", args)` — native.
- **IPC arg contract:** JS object keys arrive positional/table; each fn does
  `if type(x)=="table" then x=x.field end`; nested arrays via `cjson.decode`;
  every return is a JSON string.

## Status

### ✅ Phase 0 — Foundation (done)
Base = piqseu, rebranded. Already covers the LuaTools **core** and targets 3.4.0-beta.8:
activation (`StartAddViaLuaTools`), the download source chain, `check_apis_for_app`,
fixes, settings, locales, API manifest, auto-update. **This is deployable now.**

### ▶ Phase 1 — Verify the base on-machine (next)
Deploy Rewired over the current `luatools` plugin dir, restart Steam, confirm:
store loads, "Add via LuaTools" button appears, a test activation works. This
confirms the base before investing in the feature port. `GetMillenniumHealth` should report
Millennium `3.4.0-beta.8` or newer and all required Lua APIs available.

### Phase 2+ — Port STLT's SteamTools-Ultimate features to Lua
Ported feature clusters now include backup/restore, cache manager, manifests/depot repair,
diagnostics, Tokeer/Denuvo launch options, achievements, workshop, batch pipeline,
history/source stats, key vault, account switch/transfer, DLC config generation, update lock,
config transfer, hooks/mods, plus Gen2-style source health/companion parity panels:
- Source Health dashboard for LuaTools/Ryuu/Hubcap/fixes endpoints with redacted URLs.
- Companion / Gen2 Parity detector for official LuaTools/Rewired Manager and live plugin state.
- Redacted Support Bundle export (`backend/data/diagnostics/...`) with no cookies/API keys.
- CloudRedirect Assistant as an explicit checklist/launcher only — no silent Steam/CloudRedirect patching.

Still Windows-first; feature work should remain a Lua backend module + global IPC fn(s) +
the matching UI in `public/luatools.js`, verified on-machine.

### Explicitly NOT ported
ACCELA, SLSsteam, `linux_platform`, Proton/compat tools — Linux-only, dropped.

## Deploy (Windows)
Quit Steam. Copy the contents of `STLT-Rewired/` into
`<Steam>\millennium\plugins\luatools\` (replace). Start Steam. It's enabled already
(`enabledPlugins: ["luatools"]`).
