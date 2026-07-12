# STLT (Sigmachan) parity tracker

Reference fork: [Sigmachan/STLT](https://github.com/Sigmachan/STLT) (10.x line after 9.0.7).  
Local checkout (preferred for diffs/locale import): `F:\STLT`  
Planning doc on disk: `F:\STLT-since-9.0.7-and-clean-build.pdf`.

Rewired intentionally keeps a **Windows-first, native Lua** backend (~169 RPCs) instead of STLT’s Python HTTP bridge on `:6767`. This file tracks what is already ported, what differs by design, and what is still worth pulling over.

## Already in Rewired (from STLT / upstream UX)

| Area | Status |
|------|--------|
| Auto-pilot / `AutoFinalizeActivation` (steam://install) | Done |
| Advanced tools menu collapse | Done |
| Interactive source picker + Morrenus badges | Done (upstream-style RPCs) |
| Add ↔ Remove store button toggle | Done |
| `getPageGameName()` on add | Done |
| `sync-from-live.ps1` | Done |
| Gen2 parity panels (source health, companion, CloudRedirect, support bundle) | Done |
| Locales: en, de, ru, **uk**, **be** | Done |
| First-run setup assistant (Lua + JS modal) | Done (`setup_assistant.lua`, `GetSetupState` / `RunSetup` / `MarkSetupSeen`) |
| Self-heal on load | Done (`SelfHeal` RPC + `on_load` hook) |
| Health preflight (Windows) | Done (`health.run_health_check`, settings health panel no longer Linux-only skip) |
| Fast Download → auto-pick single source | Done (`isFastDownloadEnabled()` in add poll) |
| Big Picture gamepad polish | Done (B = back, larger targets, hint bar on menu open) |
| Update channel semver | Done (`plugin_utils.is_newer_version`, `update.json` → Sigmachan/STLT) |
| Deploy duplicate-plugin dedup | Done (`deploy.ps1`, from STLT `install.ps1`) |
| STLT reference docs in `docs/` | Done (`CHANGELOG.md`, `MILLENNIUM_3_0_ERRORS.md`, `ROADMAP-10.0.md`, `STLT-FINDINGS.md`) |

## STLT 10.x features — still open

1. **Regression test suite** — STLT `tests/`; Rewired has little automated coverage for add/remove/finalize paths.
2. **Morrenus key validation** — STLT `ValidateMorrenusKey`; Rewired shows badges but no dedicated validator RPC.
3. **jsDelivr mirror fallback** in downloads when primary manifest hosts fail.
4. **`api_manifest` stale refresh** — STLT refreshes cached manifest on TTL; Rewired may serve older cache longer.
5. **Skyflare** in default `api.json` if desired for parity with STLT catalog breadth.
6. **Denuvo diagnostics** — STLT health probes; partial coverage in Rewired health engine.

## Intentionally omitted (Linux-only per PDF §2.2)

Do **not** port into Rewired Windows builds:

- `accela_launcher.py`, `slssteam_config.py`, `linux_platform.py`
- ACCELA bundle download path, SLSsteam PlayNotOwned, `GetAccelaInfo` / `SetAccelaPath` IPC

## Suggested next ports (priority)

1. Add smoke tests for `StartLuaToolsAdd` → `PickLuaToolsAddSource` → finalize on a fixture appid.
2. Port Morrenus key validator if users report invalid-key confusion.
3. Mirror STLT download CDN fallback for manifest fetches.

## Locale notes

- **uk** — merged from local `F:\STLT\backend\locales\uk.json` via `scripts/merge_locales_from_stlt.py`.
- **be** — generated from uk/ru + Belarusian overrides (`scripts/build_be_locale.py`); re-run after uk refresh.

Supported in UI: Settings → Language, plus Steam language detection via `normalizeLuaToolsLanguage()` in `public/luatools.js`.

Refresh from local STLT after `en.json` changes:

```powershell
python F:\STLT-Rewired\scripts\merge_locales_from_stlt.py --stlt F:\STLT --locales uk
python F:\STLT-Rewired\scripts\build_be_locale.py
python F:\STLT-Rewired\scripts\build_webkit_bundle.py
```

## Deploy

```powershell
F:\STLT-Rewired\deploy.ps1
```

Rebuilds `webkit.js`, deduplicates duplicate `luatools` plugin folders, backs up live install, copies repo → Millennium plugins path. Full Steam restart recommended after deploy.
