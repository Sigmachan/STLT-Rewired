# Competitive baseline

This document tracks the official/near-official LuaTools surfaces as a reference target. The point is not to clone them line-for-line. The point is to know the product bar, keep STLT-Rewired honest, and pick differentiators that make Rewired worth using.

## Baseline sources

### Gen1 plugin archive

Local reference:

```text
C:\Users\sened\Downloads\ltsteamplugin-main.zip
```

Role in our strategy:

- minimal Millennium Lua plugin contract reference;
- useful for understanding what the official plugin considers core;
- small enough to diff mentally against Rewired;
- not a full power-user product.

Observed product shape:

- Steam-injected JS frontend;
- Lua backend;
- `luatools` plugin name;
- compact Add/Fixes/Settings surface;
- theme assets and basic deploy/sync scripts.

### Gen 2 portable app

Local reference:

```text
E:\LuaTools-win-Portable
```

Role in our strategy:

- product/UX reference;
- feature discovery source;
- proof that a Windows companion app is a reasonable direction;
- not a source-code dependency.

Observed product shape from installed files and DLL strings:

- .NET 8 / WPF portable app;
- app version `1.2.2`;
- service concepts:
  - `PluginInstallerService`;
  - `CefInjectorService`;
  - `LuaToolsApiClient`;
  - `HubcapService`;
  - `GithubProxy`;
  - `SteamAppInfoCache`;
  - `HardwareAppIdService`;
  - `CloudRedirectService`;
  - `SteamlessService`;
  - `UnlockerService`;
  - Denuvo listings/fixes/downloads.

### STLT-Rewired

Local reference:

```text
F:\STLT-Rewired
```

Role in our strategy:

- independent Windows-first power-user fork;
- integration lab for features that are awkward in the official product;
- Ryuu-first source/fixes workflow;
- safer fixes/deploy behavior;
- future base for a companion app.

## Strategic read

Gen1 answers:

> What is the smallest working LuaTools Steam plugin shape?

Gen2 answers:

> What product workflows do users expect from a polished LuaTools desktop experience?

Rewired answers:

> What can a power-user Millennium plugin + companion manager do better, safer, and faster?

## Feature baseline matrix

| Feature area | Gen1 plugin | Gen2 portable app | Rewired current | Rewired direction |
| --- | --- | --- | --- | --- |
| Steam UI plugin | yes | app-assisted | yes | keep in-Steam UX first-class |
| Desktop manager | no | yes | planned | build Rewired Manager |
| Plugin install/update | scripts | app service | deploy.ps1 | app-assisted deploy + rollback |
| Ryuu Premium | unclear/basic | not confirmed | yes | make Ryuu Manager the flagship |
| Morrenus/Hubcap | source/API path | service + stats | yes | better key validation + stats UI |
| Source health | basic | likely app-side | yes | full source health dashboard + redacted bundle |
| Fixes | basic | Denuvo/fix services | hardened + Ryuu fallback | preview, audit, unfix, attribution |
| CloudRedirect | not apparent | service visible | explicit assistant | explicit assistant, no silent patching |
| Steamless/unlocker | not apparent | service visible | explicit policy | only explicit opt-in workflows |
| Diagnostics | limited | app logs likely | redacted bundle | redacted support bundle |
| App metadata cache | limited | SteamAppInfoCache | partial | shared cache for plugin/app |
| Secrets UX | unclear | app settings | local gitignored JSON | DPAPI-backed manager + plugin sync |

## Differentiators to build

### 1. Ryuu-first experience

Official LuaTools can remain source-general. Rewired should be the best Ryuu workflow:

- Ryuu Premium session setup without leaking cookies;
- paginated Ryuu catalog search;
- Ryuu fixes fallback;
- source health checks that understand VPN/zapret/Cloudflare failure modes;
- per-app Ryuu status in Steam and in the manager.

### 2. Safe fixes pipeline

Rewired should be boringly safe:

- validate archives before extraction;
- reject path traversal and Windows ADS/path weirdness;
- write install logs for unfix;
- clean partial state;
- attribute every fix to its source;
- make 429/source outages non-fatal.

### 3. Serious deploy/rollback

Most plugin workflows fail at install/update time. Rewired should make this a strength:

- preserve local data;
- backup outside plugin collision paths;
- check Steam process state;
- validate Millennium runtime archives;
- support rollback;
- make a desktop app wrapper later.

### 4. Diagnostics bundle

Instead of Discord back-and-forth:

- collect plugin version;
- collect Millennium version;
- collect Steam process/library state;
- collect source health;
- collect redacted settings shape;
- collect relevant logs;
- never include cookies/API keys/tokens.

### 5. Companion app without daemon creep

Gen2 shows the value of a native app. Rewired should adopt the shape, not the baggage:

- one-shot manager operations;
- tray optional, not required;
- no hidden localhost bridge replacing Millennium IPC;
- no silent patching;
- explicit launch for CloudRedirect/Steamless/unlocker flows.

## Things to avoid

- Do not chase Discord approval as a product requirement.
- Do not copy closed/binary implementation details from Gen2.
- Do not introduce a Python HTTP bridge into the plugin runtime.
- Do not print or commit Ryuu/Morrenus/GitHub secrets.
- Do not silently patch SteamTools, OpenSteamTools, CloudRedirect, Steamless, or Steam Cloud layers.
- Do not add Linux/Proton complexity until the Windows path is stable.

## Immediate roadmap

### Plugin short-term

1. Keep Ryuu catalog/fixes stable.
2. Keep source health UI useful and redacted.
3. Maintain redacted diagnostics export.
4. Improve fixes manager UX:
   - source labels;
   - archive preview;
   - safe unfix status;
   - clear 429/offline state.
5. Cut release artifacts and tags.

### Manager short-term

1. Create a clean .NET 8 WPF skeleton.
2. Locate Steam/Millennium/STLT-Rewired live plugin.
3. Read/write Ryuu/Morrenus local secrets safely.
4. Validate Ryuu session and catalog.
5. Show source health dashboard.
6. Export redacted diagnostic bundle.

### Manager later

1. Install/update STLT-Rewired from GitHub releases.
2. Backup/restore live plugin.
3. Launch CloudRedirect flow explicitly.
4. Integrate richer Steam app metadata cache.
5. Add Denuvo/fixes browser if the data source is stable and legally/operationally acceptable.

## Positioning

Suggested repo/product wording:

> STLT-Rewired is an independent Windows-first LuaTools/Millennium power-user fork. It keeps the in-Steam plugin UX, adds Ryuu-first workflows, hardens fixes and deployment, and is designed to grow a companion Rewired Manager app for setup, source health, and diagnostics.

This keeps the tone technical and confident: official LuaTools is the baseline, not the authority.
