# Millennium 3.0 bridge — postmortem (RESOLVED)

Original report: 2026-06-10 · Closed: 2026-06-15

> Status: **all items below are fixed.** Kept as a postmortem so the root causes
> and the guards that prevent regression are on record. Suite: **94 tests, green,
> and clean under `-W error::ResourceWarning`.**

## 1) Millennium 3.0 API-surface gap — FIXED

**Was:** the standalone fallback in [backend/platform_bridge.py](backend/platform_bridge.py)
didn't expose the full documented 3.0 surface (`cmp_version`, `get_install_path`,
`is_plugin_enabled`, `remove_browser_module`), so backend code targeting the 3.0
contract hit `AttributeError` when run outside Millennium.

**Now:** the full surface is implemented *and realistic*, not just stubbed:
- `cmp_version` — proper `-1 / 0 / 1` numeric comparison, length-normalised.
- `get_install_path` — detects the real Millennium install dir (`$MILLENNIUM_PATH`,
  `$XDG_DATA_HOME/millennium`, `/usr/lib/millennium`, …); falls back to the Steam
  path only when none is found.
- `is_plugin_enabled` — reads Millennium's own `config.json`
  (`plugins.enabledPlugins`) under `$XDG_CONFIG_HOME/millennium`; defaults to
  `True` only when the config is missing/unreadable (a headless safety net must
  not disable a plugin).
- `remove_browser_module` — returns `True`. Browser modules exist only inside the
  live runtime, so "nothing to remove → success" is the correct no-op contract.

**Guard:** [tests/test_platform_bridge_api.py](tests/test_platform_bridge_api.py)
— full-surface presence, `cmp_version` semantics, config-driven `is_plugin_enabled`
(enabled / not-listed / malformed-config), and `get_install_path` preference.
Hermetic (isolated `XDG_*` env), so it never reads the host's real config.

## 2) Dotted IPC name flooding cef_log — FIXED

**Was:** the frontend logged via `callServerMethod('luatools', 'Logger.log', …)`.
Millennium 3.x dispatches server methods with a flat `getattr(module, name)`, so a
*dotted* name is unresolvable → `function not found: Logger.log` on **every** log
call (the 65 residual errors after the millennium-bin 3.3.0 upgrade), and the
unhandled promise rejection spammed the console.

**Now:** a flat top-level `LogFrontend()` sink in [backend/main.py](backend/main.py)
delegates to the level-specific `Logger` helper; both frontend bundles call
`'LogFrontend'` and `.catch()` the promise so a backend miss can never flood again.

**Guard:** [tests/test_ipc_surface.py](tests/test_ipc_surface.py) — `LogFrontend`
is canonical, and no frontend bundle may ship a dotted `callServerMethod` name.

## 3) ResourceWarning leaks — FIXED

**Was:** the suite emitted many `ResourceWarning: unclosed file …` traces
(accela_launcher, downloads, and several temp-config tests).

**Now:** the full suite runs clean under `python3 -W error::ResourceWarning`
(exit 0, zero warnings). The strict run is the standing check.

## Bottom line

The Millennium 3.0 bridge path is production-clean: full + realistic fallback
surface, no dotted-IPC dead ends, no leaked handles — each fix pinned by a
regression test.
