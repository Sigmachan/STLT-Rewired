# Rewired Manager product plan

Rewired Manager is the proposed independent companion app for STLT-Rewired. It should make the project feel like a serious product instead of a loose plugin fork, while keeping risky operations explicit and reversible.

## Product thesis

LuaTools should be split into two cooperating surfaces:

1. **STLT-Rewired plugin** — runs inside Steam/Millennium and handles in-Steam actions.
2. **Rewired Manager app** — a Windows desktop companion for setup, accounts, source health, repair, diagnostics, and heavyweight workflows.

This mirrors the useful parts of the Gen2 portable app without copying its implementation or giving up the in-Steam plugin UX.

## Guiding principles

- Windows-first.
- No silent credential leaks.
- No silent patching of SteamTools/Steam/cloud layers.
- Every destructive or system-level action gets a preview and rollback path.
- Ryuu/Morrenus/session material stays local and gitignored.
- Plugin remains usable without the desktop app.
- Desktop app makes hard setup easy; it does not become a required daemon.

## MVP: Ryuu Manager

The first standalone feature should be Ryuu Manager because it is high-impact and already has backend foundations in STLT-Rewired.

### MVP features

- Detect local STLT-Rewired plugin install.
- Show Ryuu session status without printing cookies.
- Save/update `ryuuSession` into the live plugin's `backend/data/secrets.local.json`.
- Test endpoints:
  - `https://generator.ryuu.lol/api/games?limit=40&page=1&search=portal`
  - `https://generator.ryuu.lol/fixes`
  - `https://generator.ryuu.lol/api/download/<appid>` availability where safe.
- Search Ryuu catalog with the same paginated API strategy as `backend/ryuu.lua`.
- Show source health for Ryuu, Morrenus, LuaTools index, GitHub/CDN.
- Export a redacted diagnostic bundle for support/debugging.

### Why Ryuu first

- Users already need authenticated Ryuu Premium flows.
- Steam webkit error reporting is bad.
- Cookies are sensitive; a native manager can make storage/validation safer.
- Source health changes quickly due VPN/zapret/Cloudflare/proxy conditions.

## MVP architecture options

### Option A: .NET 8 WPF app

Pros:

- matches Gen2's observed stack;
- natural Windows UX;
- easy file dialogs, registry/process inspection, DPAPI, tray integration;
- good fit for plugin installer/repair.

Cons:

- heavier build/release pipeline;
- UI work takes longer.

### Option B: Tauri / webview app

Pros:

- easier to reuse frontend components/styles;
- smaller-ish app feel;
- Rust backend can be very robust.

Cons:

- more moving pieces;
- Windows signing/updater complexity.

### Option C: Python/FastAPI local tool

Not recommended as the product shell. The old Python bridge failure mode is precisely what Rewired avoids. Python is fine for dev scripts and verification, not for the main user-facing runtime.

Recommended: **.NET 8 WPF**, because Gen2 proves the audience accepts a Windows desktop manager and because Steam/process/file operations are first-class there.

## App modules

### Plugin installer

- find Steam path;
- find Millennium path;
- check Millennium version;
- install/update plugin files;
- preserve `backend/data`;
- create restore point;
- roll back latest backup;
- restart Steam only after explicit confirmation.

### Ryuu Manager

- session input/import;
- cookie validation;
- catalog search;
- download/fix availability probe;
- source status dashboard;
- redacted logs.

### Source dashboard

- Ryuu Premium;
- Morrenus/hubcap;
- LuaTools fixes index;
- GitHub raw/releases;
- jsDelivr/CDN;
- router/proxy note if configured.

### Fixes manager

- list available fixes from all sources;
- show source attribution;
- preview files in archive when possible;
- apply via safe extractor;
- unfix from logged relative paths;
- never extract unsafe paths.

### Cloud/SteamTools assistant

- detect common Steam Cloud errors from `Steam/logs/cloud_log.txt`;
- identify lua/added game appids;
- offer safe options:
  - explain disabling Steam Cloud for that game;
  - launch CloudRedirect GUI;
  - collect diagnostics.
- no silent patch/provider login.

### Diagnostics bundle

- plugin version;
- Millennium version;
- Steam path;
- enabled plugin status;
- source health statuses;
- relevant log excerpts;
- redacted settings shape;
- no secrets/cookies/tokens.

## Plugin features to prioritize alongside app

1. Make Ryuu Catalog first-class in UI.
2. Make fixes modal resilient and source-attributed.
3. Add diagnostics export button.
4. Add source health widget.
5. Add clearer restart/no-license state after Add to Steam.
6. Add CloudRedirect guidance panel, not auto-patching.
7. Add import/export config for easier migration.

## Repo strategy

Current repo stays the plugin source:

```text
F:\STLT-Rewired
```

Future companion app can live either as:

```text
F:\STLT-Rewired\manager
```

or separate repo:

```text
F:\Rewired-Manager
```

Recommendation: start in a separate repo once the app skeleton exists. Keep this repo focused and buildable as a Millennium plugin.

## Initial milestone checklist

### Milestone 0: docs and positioning

- architecture docs;
- Gen1/Gen2 comparison;
- independent fork rationale;
- roadmap.

### Milestone 1: plugin stabilization

- verify live deploy after recent Ryuu/fixes work;
- improve README screenshots/usage;
- cut a GitHub release tag.

### Milestone 2: Ryuu Manager prototype

- .NET 8 WPF skeleton;
- locate plugin install;
- read/write local secrets without printing;
- Ryuu session validation;
- catalog search UI;
- source health page.

### Milestone 3: installer/rollback

- deploy STLT-Rewired from release artifact;
- preserve data;
- create/restore backup;
- Steam running preflight.

### Milestone 4: diagnostics and CloudRedirect assistant

- cloud log parser;
- redacted support bundle;
- explicit CloudRedirect launcher/guide.

## Messaging

Do not frame this as begging upstream to accept patches. Frame it as:

> STLT-Rewired is an independent Windows-first LuaTools/Millennium power-user fork and integration lab. It keeps the in-Steam plugin UX, adds Ryuu-first workflows, hardens fixes/deploy behavior, and may ship a companion desktop manager for setup and diagnostics.
