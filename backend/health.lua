-- health.lua — Millennium presence + Steam-running probe (report-only).
--
-- Faithful Lua port of health.py check_millennium_health / get_millennium_health.
-- Never launches Steam, never mutates files. The signature failure mode
-- (Millennium installed but Steam not running) usually means Steam crashed on
-- launch because Millennium is out of date for the current Steam build.

local fs          = require("fs")
local steam_utils = require("steam_utils")
local st          = require("st_util")

local M = {}

local TARGET_MILLENNIUM = "3.4.0-beta.8"

local CRASH_HINT = "If Steam crashed on launch, Millennium may be out of date " ..
    "for the current Steam build - update Millennium."

local REQUIRED_API = {
    "ready",
    "add_browser_css",
    "add_browser_js",
    "version",
    "steam_path",
}

local function load_millennium()
    local ok, mil = pcall(require, "millennium")
    if ok and type(mil) == "table" then return mil end
    return nil
end

local function get_millennium_version(mil)
    if not mil or type(mil.version) ~= "function" then return "unknown" end
    local ok, version = pcall(mil.version)
    if ok and version and version ~= "" then return tostring(version) end
    return "unknown"
end

local function compare_millennium_version(mil, version, target)
    if not mil or type(mil.cmp_version) ~= "function" or version == "unknown" then return nil end
    local ok, result = pcall(mil.cmp_version, version, target)
    if ok and type(result) == "number" and result >= -1 and result <= 1 then return result end
    return nil
end

local function api_report(mil)
    local missing = {}
    if not mil then
        for _, name in ipairs(REQUIRED_API) do table.insert(missing, name) end
        return false, missing
    end

    for _, name in ipairs(REQUIRED_API) do
        if type(mil[name]) ~= "function" then table.insert(missing, name) end
    end
    return #missing == 0, missing
end

local function millennium_installed(root)
    if root and root ~= "" and fs.is_directory(fs.join(root, "millennium")) then return true end
    -- running under the Millennium Lua host is itself proof of install
    return load_millennium() ~= nil
end

function M.get_millennium_health()
    local root = steam_utils.detect_steam_install_path() or ""
    local mil = load_millennium()
    local installed = millennium_installed(root)
    local running = st.steam_is_running()
    local version = get_millennium_version(mil)
    local cmp = compare_millennium_version(mil, version, TARGET_MILLENNIUM)
    local api_ok, missing_api = api_report(mil)
    local version_ok = cmp == nil or cmp >= 0

    local severity, hint
    if not installed then
        severity = "warn"
        hint = "Millennium was not detected. STLT requires Millennium 3.x to run. " .. CRASH_HINT
    elseif not api_ok then
        severity = "error"
        hint = "Millennium is present, but required Lua APIs are missing: " .. table.concat(missing_api, ", ") .. ". " .. CRASH_HINT
    elseif not version_ok then
        severity = "warn"
        hint = "Millennium " .. version .. " detected. STLT-Rewired targets " .. TARGET_MILLENNIUM .. "; update Millennium before debugging plugin behavior."
    elseif running then
        severity = "ok"
        hint = "Millennium " .. version .. " detected, required Lua APIs are available, and Steam is running."
    else
        severity = "warn"
        hint = "Millennium " .. version .. " detected and required Lua APIs are available, but Steam is not running. If you haven't started Steam yet, just launch it. " .. CRASH_HINT
    end

    return {
        success = true,
        millenniumInstalled = installed,
        millenniumVersion = version,
        targetMillenniumVersion = TARGET_MILLENNIUM,
        versionCompare = cmp,
        versionCompatible = version_ok,
        requiredApiAvailable = api_ok,
        missingApi = st.A(missing_api),
        steamRunning = running,
        severity = severity,
        hint = hint,
    }
end

-- ── Windows/Linux preflight report (port of health.py run_health_check) ───────

local http_client = require("http_client")
local config      = require("config")
local m_utils     = require("utils")

local SEV_ORDER = { fail = 3, warn = 2, ok = 1, info = 0, skip = -1 }

local function _check(id_, label, status, detail, fix)
    local c = { id = id_, label = label, status = status, detail = detail or "" }
    if fix then c.fix = fix end
    return c
end

function M.ensure_stplugin_dir()
    local base = steam_utils.detect_steam_install_path() or ""
    if base == "" then return false end
    local d = fs.join(base, "config", "stplug-in")
    if not fs.exists(d) then
        fs.create_directories(d)
    end
    return fs.exists(d)
end

local function _chk_platform()
    return _check("platform", "Platform", "info", "Windows (SteamTools / stplug-in)")
end

local function _chk_steam_root()
    local root = steam_utils.detect_steam_install_path()
    if root and root ~= "" and fs.is_directory(root) then
        return _check("steam_root", "Steam installation", "ok", root)
    end
    return _check("steam_root", "Steam installation", "fail",
        "Steam install not found. Install Steam and restart the client.")
end

local function _chk_stplugin_dir()
    local base = steam_utils.detect_steam_install_path() or ""
    local d = base ~= "" and fs.join(base, "config", "stplug-in") or ""
    if d == "" then
        return _check("stplugin_dir", "stplug-in directory", "fail", "Could not resolve stplug-in path.")
    end
    if fs.is_directory(d) and M.ensure_stplugin_dir() then
        return _check("stplugin_dir", "stplug-in directory", "ok", d)
    end
    return _check(
        "stplugin_dir", "stplug-in directory", "fail",
        d .. " is missing or not writable.",
        { label = "Create stplug-in folder", ipc = "EnsureStpluginDir", args = {} }
    )
end

local function _chk_installed_lua()
    local base = steam_utils.detect_steam_install_path() or ""
    local d = base ~= "" and fs.join(base, "config", "stplug-in") or ""
    local n = 0
    if d ~= "" and fs.is_directory(d) then
        local files = fs.list(d)
        if files then
            for _, e in ipairs(files) do
                if e.name and e.name:match("%.lua$") then n = n + 1 end
            end
        end
    end
    return _check("installed_lua", "Installed .lua scripts", "info", tostring(n) .. " activated game(s).")
end

local function _chk_millennium()
    local mil = M.get_millennium_health()
    if mil.severity == "error" then
        return _check("millennium", "Millennium", "fail", mil.hint or "Millennium API issue")
    end
    if mil.severity == "warn" then
        return _check("millennium", "Millennium", "warn", mil.hint or "Millennium warning")
    end
    return _check("millennium", "Millennium", "ok", mil.hint or "Millennium OK")
end

local function _chk_network()
    local resp = http_client.get("https://api.github.com/", {
        headers = { ["User-Agent"] = config.USER_AGENT or "LuaTools-Health/1.0" },
        timeout = 6,
    })
    if resp and resp.status and resp.status < 500 then
        return _check("network", "Network to sources", "ok", "github.com reachable.")
    end
    return _check("network", "Network to sources", "warn",
        "Could not reach github.com — manifest sources may be blocked.")
end

local function _chk_app(appid)
    local out = {}
    local base = steam_utils.detect_steam_install_path() or ""
    local d = base ~= "" and fs.join(base, "config", "stplug-in") or ""
    local lua_path = d ~= "" and fs.join(d, tostring(appid) .. ".lua") or ""
    if lua_path == "" or not fs.exists(lua_path) then
        table.insert(out, _check("app_activated", "App " .. appid .. ": activated", "warn",
            "No .lua installed for this app yet."))
        return out
    end
    local text = m_utils.read_file(lua_path) or ""
    local has_owner = text:match("%s*addappid%s*%(%s*" .. appid) or text:match("%s*addappid%s*%(%s*%d+")
    local has_key = text:match('addappid%s*%(.-%d+%s*,.-%d+%s*,.-%s*"[a-fA-F0-9][a-fA-F0-9]+"')
    table.insert(out, _check("app_activated", "App " .. appid .. ": .lua installed", "ok", lua_path))
    if has_owner then
        table.insert(out, _check("app_ownership", "App " .. appid .. ": ownership grant", "ok", "Base addappid() present."))
    else
        table.insert(out, _check("app_ownership", "App " .. appid .. ": ownership grant", "fail",
            "No base addappid() line — re-add the game."))
    end
    if has_key then
        table.insert(out, _check("app_keys", "App " .. appid .. ": depot keys", "ok", "Depot key present."))
    else
        table.insert(out, _check("app_keys", "App " .. appid .. ": depot keys", "warn",
            "No 64-char depot key found — depots may stay encrypted."))
    end
    return out
end

function M.run_health_check(appid, quick)
    local checks = {
        _chk_platform(),
        _chk_steam_root(),
        _chk_stplugin_dir(),
        _chk_installed_lua(),
        _chk_millennium(),
    }
    if not quick then
        table.insert(checks, _chk_network())
    end
    if appid and tonumber(appid) and tonumber(appid) > 0 then
        for _, c in ipairs(_chk_app(tonumber(appid))) do
            table.insert(checks, c)
        end
    end

    local worst = "ok"
    for _, c in ipairs(checks) do
        local s = c.status
        if (s == "fail" or s == "warn") and (SEV_ORDER[s] or 0) > (SEV_ORDER[worst] or 0) then
            worst = s
        end
    end

    local fixes = {}
    local seen = {}
    for _, sev in ipairs({ "fail", "warn" }) do
        for _, c in ipairs(checks) do
            if c.status == sev and c.fix then
                local key = tostring(c.fix.ipc) .. "|" .. tostring(c.fix.label)
                if not seen[key] then
                    seen[key] = true
                    local fx = {}
                    for k, v in pairs(c.fix) do fx[k] = v end
                    fx.for = c.id
                    table.insert(fixes, fx)
                end
            end
        end
    end

    local n_fail, n_warn = 0, 0
    for _, c in ipairs(checks) do
        if c.status == "fail" then n_fail = n_fail + 1 end
        if c.status == "warn" then n_warn = n_warn + 1 end
    end

    local summary
    if worst == "ok" then
        summary = "All prerequisites look good — activations should download normally."
    elseif worst == "warn" then
        summary = "Mostly OK, " .. n_warn .. " warning(s) to review."
    else
        summary = n_fail .. " blocking issue(s) found — see the fix list."
    end

    return {
        success = true,
        platform = "windows",
        overall = worst,
        summary = summary,
        checks = checks,
        fixes = fixes,
        generatedAt = os.time(),
    }
end

return M
