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

local CRASH_HINT = "If Steam crashed on launch (python311.dll 0xc0000409), " ..
    "Millennium may be out of date for the current Steam build - update Millennium."

local function millennium_installed(root)
    if root and root ~= "" and fs.is_directory(fs.join(root, "millennium")) then return true end
    -- running under the Millennium Lua host is itself proof of install
    local ok, mil = pcall(require, "millennium")
    return ok and type(mil) == "table"
end

function M.get_millennium_health()
    local root = steam_utils.detect_steam_install_path() or ""
    local installed = millennium_installed(root)
    local running = st.steam_is_running()

    local severity, hint
    if not installed then
        severity = "warn"
        hint = "Millennium was not detected. STLT requires Millennium 3.x to run. " .. CRASH_HINT
    elseif running then
        severity = "ok"
        hint = "Millennium detected and Steam is running. " .. CRASH_HINT
    else
        severity = "warn"
        hint = "Millennium is installed but Steam is not running. If you haven't started Steam yet, just launch it. " .. CRASH_HINT
    end

    return {
        success = true,
        millenniumInstalled = installed,
        steamRunning = running,
        severity = severity,
        hint = hint,
    }
end

return M
