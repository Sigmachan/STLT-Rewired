# STLT (Sigmachan) parity tracker

Reference fork: Sigmachan/STLT (10.x line after 9.0.7; GitHub listing is gone/private —
use a local checkout for diffs).  
Local checkout (preferred for diffs/locale import): `F:\STLT`  
Planning doc on disk: `F:\STLT-since-9.0.7-and-clean-build.pdf`.  
Live Rewired update channel: `Sigmachan/STLT-Rewired` (`backend/update.json`).

Rewired intentionally keeps a **Windows-first, native Lua** backend (~169 RPCs) instead of STLT’s Python HTTP bridge on `:6767`. This file tracks what is already ported, what differs by design, and what is still worth pulling over.

## Already in Rewired (from STLT / upstream UX)

| Area | Status |
|------|--------|
| Auto-pilot / `AutoFinalizeActivation` (steam://install) | Done |
| Advanced tools menu collapse | Done |
| Interactive source picker + ManifestHub badges | Done (upstream-style RPCs) |
| Add ↔ Remove store button toggle | Done |
| `getPageGameName()` on add | Done |
| `sync-from-live.ps1` | Done |
| Gen2 parity panels (source health, companion, CloudRedirect, support bundle) | Done |
| Locales: en, de, ru, **uk**, **be** | Done (Rewired branding in all shipped locales via `scripts/rebrand_locales.py`) |
| First-run setup assistant (Lua + JS modal) | Done (`setup_assistant.lua`, `GetSetupState` / `RunSetup` / `MarkSetupSeen`) |
| Self-heal on load | Done (`SelfHeal` RPC + `on_load` hook) |
| Health preflight (Windows) | Done (`health.run_health_check`, settings health panel no longer Linux-only skip) |
| Fast Download → auto-pick single source | Done (`isFastDownloadEnabled()` in add poll) |
| Big Picture gamepad polish | Done (B = back, larger targets, hint bar on menu open) |
| Update channel semver | Done (`plugin_utils.is_newer_version`, `update.json` → Sigmachan/STLT-Rewired) |
| Deploy duplicate-plugin dedup | Done (`deploy.ps1`, from STLT `install.ps1`) |
| STLT reference docs in `docs/` | Done (`CHANGELOG.md`, `MILLENNIUM_3_0_ERRORS.md`, `ROADMAP-10.0.md`, `STLT-FINDINGS.md`) |
| Manifest auto-updater | Done (`manifest_auto_updater.lua`, `RunManifestAutoUpdate`, setting `general.autoUpdateManifests`) |
| Ryuu catalog search | Done (local `games.json` cache via `WarmRyuuCatalogCache` / `SearchRyuuCatalog`) |
| ManifestHub key validation | Done (`ValidateManifestHubKey` + `ValidateMorrenusKey` alias, settings “Test key” button) |
| Stale manifest refresh | Done (`manifests.update_manifests` re-fetches when steamcmd gid changes, prunes old depot files) |

## STLT 10.x features — still open

1. **Regression test suite** — STLT `tests/`; Rewired has little automated coverage for add/remove/finalize paths.
2. **jsDelivr mirror fallback** in downloads when primary manifest hosts fail — **Done** (`backend/github_mirror.lua`, wired into `manifests.lua` + `api_manifest.lua`).
3. **Skyflare** in default `api.json` if desired for parity with STLT catalog breadth.
4. **Denuvo diagnostics** — STLT health probes; partial coverage in Rewired health engine.

## Intentionally omitted (Linux-only per PDF §2.2)

Do **not** port into Rewired Windows builds:

- `accela_launcher.py`, `slssteam_config.py`, `linux_platform.py`
- ACCELA bundle download path, SLSsteam PlayNotOwned, `GetAccelaInfo` / `SetAccelaPath` IPC

## Suggested next ports (priority)

1. Add smoke tests for `StartLuaToolsAdd` → `PickLuaToolsAddSource` → finalize on a fixture appid.
2. Mirror STLT download CDN fallback for manifest fetches.

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
