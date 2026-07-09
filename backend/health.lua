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

return M
