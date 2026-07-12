# STLT — useful findings mined from the reference repos

> Output of studying the `_refs/` stash (upstream + forks + live ps.lua.tools installers)
> against STLT. Prioritised **Windows-first** per Kira (2026-07; Linux port = "worth
> doing, later"). Confidence: ✓ = verified against source by main agent; ~ = miner-asserted,
> spot-check before acting. Lives in gitignored `_refs/`.

Sources: 5 architect miners (`agent://0-LinuxParent`,`1-UpstreamJS`,`2-ApiInfra`,`3-OpenSteamTool`,`4-Siblings`) + live install scripts (`artifact://14`,`15`).

---

## ✅ IMPLEMENTATION STATUS (2026-07 — all shipped, suite green)

All tiers implemented in one pass. Verification: full `unittest` suite **137 tests, 43 new all green**; the 12 remaining failures are **pre-existing** Linux/Steam-env tests that don't hold on the Windows dev box (confirmed identical on pristine HEAD). Syntax sweep 73 files OK; `node --check` OK on both JS files; ResourceWarning-strict run clean. Plugin version NOT bumped (release is Kira's call). Everything still needs on-machine acceptance (real Steam/Millennium) — the dev box can't run the webkit UI or a live activation.

| # | Finding | Status | Where |
|---|---|---|---|
| 1 | api.json endpoints + Morrenus repoint + init_apis self-heal | ✅ done | api.json, downloads.py:1721, main.py:386, steamtools.py:336, options.py:98, api_manifest.py |
| 2 | Windows installer hardening (dedup/artifact-check/TLS/retry) | ✅ done | install.ps1 (+ install.sh mirror) |
| 3 | /health endpoint + backend-down banner | ✅ done | web_bridge_server.py, health payload, luatools_bridge.js |
| 4 | venv pre-build + fallback | ✅ done | install.ps1, main.lua |
| 5 | Per-game update lock (ACF AutoUpdateBehavior + read-only) | ✅ done | acf_writer.py + main.py IPC SetGameUpdatesDisabled/GetGameUpdateLockStatus |
| 6 | jsDelivr mirror + 404 early-out | ✅ done | downloads.py _try_with_github_proxy |
| 7 | Morrenus key validation + quota | ✅ done | main.py ValidateMorrenusKey |
| 8 | Download hardening | ⚠️ scoped | sha256 verify in auto_update.py; stall-watchdog + Cloudflare-HTML SKIPPED (httpx read-timeout + validate_zip_archive already cover these) |
| 9 | Windows Denuvo diagnostics (SAC/OST/Defender) | ✅ done | steamtools.py _windows_denuvo_diagnostics in diagnose_app |
| 10 | Millennium-crash detection | ✅ done | health.py + main.py IPC GetMillenniumHealth |
| 11 | SLSsteam YAML corruption fix (ruamel round-trip) | ✅ done | slssteam_config.py |
| 12 | LD_AUDIT two-lib chain + ACCELA launch_debug/AppImage | ✅ done | linux_platform.py, ui_injector.py, accela_launcher.py |
| 13 | Native-Lua backend migration | 📝 doc-only | CLAUDE.md §2 corrected + Lua-IPC contract; full rewrite deliberately NOT done (violates §9.2 no-big-bang — strangler-fig follow-up) |

New tests: `tests/{test_core_hardening,test_update_lock,test_health_probe,test_slssteam_writer}.py`.

## TIER 1 — do now (cheap, high-value, Windows/all-platform)

### 1. ✓ Fix stale `api.json` + hardcoded Morrenus host (dead endpoints)
- STLT `backend/api.json`: Morrenus = `manifest.morrenus.xyz` (OLD); TwentyTwo free entry = `twentytwocloud.com/secure_download?auth=1771526723_...` (**token ≈ Feb-2026, expired now**); **Skyflare source missing**.
- Upstream (`lt_api_links/load_free_manifest_apis`, both active forks) migrated Morrenus → `hubcapmanifest.com` and TwentyTwo → `api.twentytwocloud.com/download?appid=<appid>`, and lists Skyflare (`raw.githubusercontent.com/skyflarefox/Skyapi/refs/heads/main/<appid>.zip`).
- Hardcoded `manifest.morrenus.xyz` in **4 spots**: `api.json:5`, `downloads.py:1721` (status), `main.py:386` (user/stats), `steamtools.py:336` (generate/manifest); + help text `settings/options.py:98`. (Do NOT touch `downloads.py:136` `applist.morrenus.xyz` — different subdomain, likely still live.)
- Also: `api_manifest.py:init_apis()` only pulls the remote list when `api.json` is **absent** → shipped file never self-heals.
- **Action:** curl-verify `hubcapmanifest.com` vs `manifest.morrenus.xyz` liveness → repoint the 4 refs (keep old as fallback only if still resolving); replace the dead TwentyTwo free entry with `api.twentytwocloud.com/download?appid=<appid>` (or delete — the premium tier-2 in `downloads.py:953` already uses the clean URL); add Skyflare; add a TTL/version refresh to `init_apis` so stale bundled lists re-fetch.

### 2. ✓ Harden the Windows installer (`install.ps1`)  — from live `ps.lua.tools/install-plugin.ps1`
STLT's `install.ps1` is ~100 lines (locate Steam → copy → venv+pip). The live LuaTools installer (clem/Waike, 679 lines) has battle-tested robustness STLT lacks:
- **Duplicate-plugin-folder dedup** — scans BOTH `<Steam>\millennium\plugins` and legacy `<Steam>\plugins` for any folder whose `plugin.json .name == "luatools"`; 1 → update in place, >1 → remove all + reinstall single canonical. **Two folders w/ same plugin name = Millennium crashes on enable.** STLT is exposed (name `luatools`, and MS3 migrates the legacy path on boot). *(highest-value installer fix)*
- **Judge success by artifacts, not exit code** (run sub-installers with relaxed EAP + try/catch; check files-on-disk).
- **Fetch resilience:** mirror list + 3× retry each + browser UA (dodges 403 bot-protection); HttpClient 60s timeout; download to an ASCII **Steam** dir not `%TEMP%` (8.3 short-path breaks on non-ASCII usernames).
- **`Expand-Archive` fallback** when native `ZipFile` extraction throws.
- **TLS 1.2 pin** (`[Net.SecurityProtocolType]::Tls12`) + `chcp 65001` UTF-8.
- **Global `trap`** → localized error page with "your ISP is likely blocking our CDN — use a VPN" guidance + FAQ link (en/pt-BR/es/fr).
- **Enable-Plugin**: idempotent merge of `"luatools"` into `millennium/config/config.json` → `plugins.enabledPlugins`.
- **Cleanup**: remove `package\beta`, `steam.cfg`, `SteamCmdForceX86` regkeys, reset `WantsOfflineMode 1→0` in `loginusers.vdf`; start Steam `-clearbeta`.
- **Action:** port the dedup scan + artifact-success + retry/UA + Expand-Archive fallback + TLS1.2 + ISP-block message into `install.ps1`. Skip i18n for now.
- Note: the live installer pulls the plugin from `github.com/piqseu/ltsteamplugin/releases` → **piqseu is the live canonical LuaTools** (branch 2 = clemdotla `steamtools-collection`).

### 3. ~ Add `/health` endpoint + post-spawn liveness probe (cross-platform — Windows spawn dies silently too)
- STLT `web_bridge_server.py` serves only `/rpc` + static; `run()` `sys.exit(1)` on port collision → total silent backend death (STLT's documented #1 risk). No way for the UI to tell "backend down" from "method failed".
- LuaToolsLinux parent has a 3-line `/health` GET (`200 {success, service}`) + a starter that polls `http://127.0.0.1:38495/health` 5× and prints a visible failure.
- **Action:** add the `/health` handler to `do_GET`; have `luatools_bridge.js` (or `main.lua`) probe it after spawn and render a visible "backend down — check the bridge log" banner. Cheap, kills the worst silent-failure UX.

### 4. ~ venv bootstrap fallback / pre-build (cross-platform)
- `main.lua` builds `.venv` at first launch with errors suppressed (`2>/dev/null`); if venv fails there's no dep-install fallback → backend dead. (Linux also hits PEP-668 without `--break-system-packages`.)
- **Action (Windows-relevant):** pre-create the venv at **install time** in `install.ps1` so first run isn't racing network + Steam startup; surface pip failure instead of swallowing it. (Linux: add `pip install --user --break-system-packages` fallback later.)

---

## TIER 2 — medium value, worth doing

### 5. ~ Per-game update lock (ACF `AutoUpdateBehavior` + read-only) — the UI already claims this but the backend doesn't do it
- `luatools.js:3772` advertises "Auto-updates disabled (recommended for cracked games)" but there is **no backend IPC that freezes a single game**. `downloads.py:631` always comments out `setManifestid` (force latest); `steamtools.py:786` only *reads* `AutoUpdateBehavior`; `SetSteamUpdateBlock` is a GLOBAL `steam.cfg` block (breaks CloudRedirect per Devuvo).
- Refs: `lt_api_links/LuaToolsValidator.ps1` (set ACF `AutoUpdateBehavior=1` + mark `.acf` read-only, clean revert) and `LuaTools-appid-manager` (marker-based `setManifestid` re-pin via a `-- LUATOOLS: UPDATES DISABLED!` sentinel).
- **Action:** add `set_game_update_lock(appid, bool)` in `acf_writer.py`/`steam_version.py` (patch `AutoUpdateBehavior` + toggle read-only, Win `FILE_ATTRIBUTE_READONLY` / Linux `chmod 0o444`), + a marker so `_process_and_install_lua` re-pins instead of blindly commenting `setManifestid`; wire an IPC + the existing UI toggle. Reconcile value semantics (STLT reads `==2` as disabled; ref writes `1`).

### 6. ~ jsDelivr as a 2nd GitHub mirror + 404 early-out (cross-platform, cheap)
- STLT `_try_with_github_proxy` (`downloads.py:64`) has ONE fallback (`luatools.vercel.app/api/github`, `config.py:23`). If that Vercel proxy is down, all `github_repos`-tier + `raw.githubusercontent` fetches die.
- OpenSteamTool uses `cdn.jsdelivr.net/gh/{owner}/{repo}@{ref}/{path}` and breaks the mirror loop on 404 (all mirrors serve identical bytes). *(jsDelivr GH-mirror pattern independently confirmed in piqseu's own build, which loads SteamDB ext via jsDelivr.)*
- **Action:** add a jsDelivr rewrite (`raw.githubusercontent.com/{o}/{r}/{b}/{p}` → `cdn.jsdelivr.net/gh/{o}/{r}@{b}/{p}`) as a second fallback + 404 early-out. Also helps `steamtools.py` MH-backup mirror.

### 7. ~ Morrenus API-key validation + quota (cross-platform UX)
- `settings/manager.py:475 get_morrenus_api_key()` just stores/returns — no format check, no liveness. Typo'd/expired/quota-exhausted key = silent download failures.
- Ref `manifests.ps1`: format regex `^smm_[0-9a-f]{96}$` + `GET hubcapmanifest.com/api/v1/user/stats?api_key=` → `{username, can_make_requests, daily_usage, daily_limit}`.
- **Action:** `validate_morrenus_key()` + "Test key" button (STLT already has `key_vault.py`).

### 8. ~ Download hardening (cross-platform)
- Ref `SteamDowngrader.ps1`/`millennium.ps1`: no-progress "stuck download" watchdog (abort + clean partial after N s of 0 bytes), Cloudflare-HTML-not-ZIP detection (first bytes not `PK`/content is `<html` → treat as block, advance source immediately instead of waiting the timeout), and SHA256 verify against known GitHub asset digest.
- **Action:** add a no-progress watchdog + content-type/first-bytes check to `downloads.py`/`http_client.py`; SHA256 verify in `auto_update.py` where a digest is known.

### 9. ~ Windows Denuvo diagnostics: SAC / OST / Defender (Windows-specific)
- Ref `Devuvo.ps1`: detects Smart App Control (`HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy` — SAC silently blocks unsigned `tokeer_launcher.exe`), OpenSteamTool presence (registry-ticket vs GBE/tokeer strategy), Defender exclusions for Denuvo AppIDs.
- STLT `diagnose_app` covers Goldberg/conflicts/manifests but none of these; `tokeer_launcher.py` writes launch options blind.
- **Action:** add SAC-state read + OST-presence + Defender-exclusion suggestion (report-only, STLT's safe posture) into `diagnose_app`/`tokeer_launcher` for the known Denuvo AppIDs.

### 10. ~ Millennium-crash-on-launch detection (Windows-relevant)
- Ref `Devuvo.ps1 Start-SteamAndWait`: after launch, watch ~15s for early crash (`python311.dll 0xc0000409` = Millennium out of date for current Steam build) → tells user "update Millennium — NOT re-activate".
- **Action:** add a distinct `health.py` check that distinguishes "files placed fine but Millennium is crashing Steam" from "activation failed", with concrete remediation.

---

## TIER 3 — Linux (real, but "later" per Kira)

### 11. ✓/~ SLSsteam config writer corrupts nested YAML — and STLT auto-calls it (BUG, not just a gap)
- `slssteam_config.py:57-116` (`_write_yaml`) round-trips SLSsteam's `config.yaml` through a **flat `Key: value` parser** that drops every comment and every nested structure (AdditionalApps/DlcData/FakeAppIds/IdleStatus). SLSsteam's real config is nested (yaml-cpp). STLT invokes this **automatically** on activation (`live_apply.py:168`) and self-heal (`setup_assistant.py:154`).
- The parent avoided it with line-preserving surgical editors. STLT already ships **`ruamel.yaml==0.18.6` in requirements.txt but doesn't use it here.**
- **Action (when back on Linux):** rewrite `set_value` as a line-preserving editor (atomic `.tmp`+`os.replace`) OR use the already-bundled ruamel round-trip mode; port `_remove_from_additional_apps`. *Data-corruption severity — highest of the Linux items.*

### 12. ~ LD_AUDIT + ACCELA resolution
- `linux_platform.py` explicit steam.sh patch writes `LD_AUDIT=SLSsteam.so` only; SLSsteam issue #65 requires `library-inject.so:SLSsteam.so`. (Gated behind confirm, but broken when used.)
- `accela_launcher.py` resolves only `run.sh`; parent prefers `launch_debug.sh` (logs errors) and handles AppImage; STLT runs ACCELA non-blocking with no returncode check → download failures invisible.

---

## STRATEGIC — verified feasible, large effort

### 13. ✓ Native-Lua backend (piqseu pattern) — eliminates STLT's #1 risk
- **Verified:** piqseu's `backend/http_client.lua` = `require("http")` → `m_http.get/head/post`; `backend/main.lua` requires `json`/`utils`/`fs`/`http`/`millennium` in-sandbox; `public/luatools.js` calls `Millennium.callServerMethod` directly (no shim, no `:38495`, no Python, no venv). Same Millennium 3.0.
- So STLT's `CLAUDE.md §2` assumption ("HTTP moved out of the sandbox; no sanctioned spawn") is **wrong** → **correct it regardless of migration**.
- A native-Lua backend removes `web_bridge_server.py`, `platform_bridge.py`, `luatools_bridge.js`, the runtime venv/pip build, and port 38495 — killing port-collision, silent-venv-death, and future-sandbox risk in one move, and it **degrades gracefully** (UI/activation/settings survive even if download-spawn is blocked).
- **Cost:** STLT has ~48 Python modules (httpx/bs4/ruamel/DPAPI/zip-validation) — a full port is large. Do it strangler-fig: hot-path/pure-HTTP methods to Lua first; heavy modules either ported or invoked per-call via `utils.exec` (no persistent server). Reference the exact Millennium Lua-IPC contract piqseu documents: JS object keys → **alphabetical positional** Lua args; return `cjson.encode(...)` strings (bridge doesn't deep-serialize); `cjson.decode` nested args; `_G["Logger.log"]` dotted-global. Port that contract into CLAUDE.md first.

---

## Junk / do-not-trust (flagged so we don't waste time)
- `steam-lua-tools-multiprofile` (C#): **decoy** — a MetaTrader Expert-Advisor file distributor, zero Steam code. Don't run the binary.
- `steam-ecosystem-engine-Jhonfran00` (HTML): **SEO/obfuscated-JS landing page**, no real tool. Don't run.
- `luatools-installer-clemdotla`: targets Millennium 2.x, mostly anti-patterns (destructive steam.cfg delete, remote line-strip + iex). Only crumb: sentinel-file presence detection (dwmapi.dll/xinput1_4.dll = SteamTools).

---

## 🛡️ PRODUCTION-HARDENING PASS (2026-07 — review → remediate → re-verify)

Three independent architect reviews of the change set; every real finding remediated (4 executor clusters + parent), then re-verified.

**Fixed — High**
- ACCELA `run_with_zip` non-blocking `Popen` used unread `PIPE`s → deadlock once ACCELA filled the ~64KB pipe buffer (silently stalled the primary Linux download). Now `DEVNULL` on the non-blocking path; `PIPE` only when `block=True`. `accela_launcher.py`
- Windows spawn `start "" /b cmd /c "<path>"` broke on the default `C:\Program Files (x86)\Steam` (cmd quote-stripping on `(x86)`) → bridge never launched. Now `start "" /b "<launcher>"`. `main.lua`

**Fixed — Medium**
- Installer wiped the target's `.venv` + `data/` on upgrade (violated §11) → now preserved across the wipe; pip failure downgraded to WARN when a usable venv already existed. `install.ps1` + `install.sh`
- `main.lua`: Windows bridge output now logged (console python + redirect) so the banner points at a real log; `on_unload` now CIM kill-by-commandline (taskkill/wmic were dead on Win11 24H2); Linux PEP-668 fallback gained `--user`.
- `bridge.js`: nativeCall fallback re-scoped to connection-level failures only — server-answered RPC errors now surface instead of being masked.
- `api.json` stale-refresh made atomic (`write_text` → `.tmp`+`os.replace`); `init_apis` lock-guarded. `utils.py` + `api_manifest.py`
- Dead per-game update-lock `.lua` marker helpers deleted (ACF read-only lock is the freeze; §4 `setManifestid` untouched); `diagnose_app` `updatesDisabled` now agrees with `GetGameUpdateLockStatus` (AutoUpdateBehavior∈{1,2} OR read-only `.acf`). `acf_writer.py` + `steamtools.py`

**Fixed — Low** manifest_url digest · pending_zip `.tmp`+cleanup · `/health` `success` field · static-GET path-traversal boundary · acf `.tmp` orphan cleanup · health false-"crashed" wording · health ruamel dep check · `repair_steam_launcher` SLSsteam-dir resolution · slssteam line-fallback nested-key guard · install.sh realpath dedup · install.ps1 `-LiteralPath` · CLAUDE.md §13 domains + §10 banner-shipped + test count · test-stub leak (httpx/Millennium restored) · + denuvo-probe tests.

**Consciously deferred (Low, documented)**
- CORS `*` on `/rpc` (localhost CSRF) — pre-existing; restricting needs the exact Steam webkit origin (can't verify off-machine without risking all IPC).
- Mirror chain triggers on connection-level failures, not HTTP-error statuses — dominant blocked-region case works; a full fix means changing how the load-bearing download helpers signal HTTP errors.
- No jsdom JS-logic harness (no JS test runner in-repo; the one real bug — nativeCall scoping — is fixed; `node --check` + `health_payload` test cover the rest).
- `ValidateMorrenusKey` unit test (main.py's import chain isn't loadable in the lean/no-httpx test env; correct by inspection).

**Re-verify:** 133 tests, green except the same 12 pre-existing Linux/Steam-env failures (identical set vs pristine HEAD); ResourceWarning-strict clean; 73 files syntax-OK; `node --check` OK.
